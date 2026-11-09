#!/bin/sh
# statusppe-worker — root 常驻采样：PPE 硬件 offload 流数与转发速率
# 由 /etc/init.d/statusppe 以 procd 启动，每 5 秒采样一次
# 输出 /tmp/statusppe.json（0644，uhttpd CGI 以 nobody 身份可读）
ST=/tmp/statusppe.state
TMP=/tmp/statusppe.json

while :; do
	flows=0
	pkts=0
	for p in /sys/kernel/debug/ppe0/bind /sys/kernel/debug/ppe1/bind; do
		[ -r "$p" ] || continue
		n=$(grep -c 'packets=' "$p" 2>/dev/null)
		[ -n "$n" ] || n=0
		flows=$((flows + n))
		k=$(grep -o 'packets=[0-9]*' "$p" 2>/dev/null | cut -d= -f2 | awk '{s+=$1} END{print s+0}')
		pkts=$((pkts + k))
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

	printf '{"flows":%d,"pps":%d,"packets":%d,"ts":%d}\n' "$flows" "$pps" "$pkts" "$now" > "$TMP.tmp"
	mv "$TMP.tmp" "$TMP"
	chmod 644 "$TMP" 2>/dev/null

	sleep 5
done
