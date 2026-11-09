#!/bin/sh
# statusppe-worker — root 常驻采样：PPE 硬件 offload 占用（分引擎 + IPv4/IPv6 细分）
# 由 /etc/init.d/statusppe 以 procd 启动，每 5 秒采样一次
# 输出 /tmp/statusppe.json（0644，uhttpd CGI 以 nobody 身份可读）
# 结构：{"ppe0":{"t":34,"v4":34,"v6":0},"ppe1":{...},"pps":137,"hw":1,"ts":...}
ST=/tmp/statusppe.state
TMP=/tmp/statusppe.json

while :; do
	hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw 2>/dev/null)
	[ "$hw" = "1" ] || hw=0

	t0=0; a0=0; b0=0; t1=0; a1=0; b1=0
	pkts=0
	for p in /sys/kernel/debug/ppe0/bind /sys/kernel/debug/ppe1/bind; do
		[ -r "$p" ] || continue
		t=$(grep -c 'packets=' "$p" 2>/dev/null); [ -n "$t" ] || t=0
		a=$(grep -c 'IPv4' "$p" 2>/dev/null); [ -n "$a" ] || a=0
		b=$(grep -c 'IPv6' "$p" 2>/dev/null); [ -n "$b" ] || b=0
		k=$(grep -o 'packets=[0-9]*' "$p" 2>/dev/null | cut -d= -f2 | awk '{s+=$1} END{print s+0}')
		pkts=$((pkts + k))
		case "$p" in
			*ppe0*) t0=$t; a0=$a; b0=$b ;;
			*ppe1*) t1=$t; a1=$a; b1=$b ;;
		esac
	done

	now=$(date +%s)
	pps=0
	if [ -s "$ST" ]; then
		read lastt lastk < "$ST" 2>/dev/null
		if [ -n "$lastt" ] && [ -n "$lastk" ]; then
			dt=$((now - lastt))
			if [ "$dt" -gt 0 ] && [ "$pkts" -ge "$lastk" ]; then
				pps=$(( (pkts - lastk) / dt ))
			elif [ "$dt" -le 0 ]; then
				pps=0
			fi
		fi
	fi
	echo "$now $pkts" > "$ST"

	printf '{"ppe0":{"t":%d,"v4":%d,"v6":%d},"ppe1":{"t":%d,"v4":%d,"v6":%d},"pps":%d,"hw":%d,"ts":%d}\n' \
		"$t0" "$a0" "$b0" "$t1" "$a1" "$b1" "$pps" "$hw" "$now" > "$TMP.tmp"
	mv "$TMP.tmp" "$TMP"
	chmod 644 "$TMP" 2>/dev/null

	sleep 5
done
