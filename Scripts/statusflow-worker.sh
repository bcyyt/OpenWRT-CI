#!/bin/sh
# statusflow-worker v3 — 每客户端上下行实时速率 + 今日/累计流量统计
#
# 双源（每 2 秒差分）：
#   A) /proc/net/nf_conntrack — 每流 orig/reply 独立计数（精确双向）
#   B) /sys/kernel/debug/ppe{0,1}/bind — PPE 硬件转发累计（按 conntrack 比重拆向）
#   首次见到的表项不计增量（防止长流历史字节跳变）
#
# 统计（持久化 /etc/statusflow/totals.state，每 10 分钟 + 停机/跨天时落盘）：
#   tu/td = 今日 上行/下行 累计；gu/gd = 总计 上行/下行（跨天 tu/td 归零，gu/gd 续算）
#
# 输出 /tmp/statusflow.json：
#   {"ts":N,"<ip>":{"u":<B/s>,"d":<B/s>,"tu":N,"td":N,"gu":N,"gd":N}}
# 注意：字节计数一律 %.0f 输出（busybox awk 的 %d 会 32 位饱和）

D=/tmp/statusflow.d
TMP=/tmp/statusflow.json
PD=/etc/statusflow
PERSIST=$PD/totals.state
mkdir -p $D $PD

TODAY=$(date +%F)
LASTDAY=$TODAY
ROUNDS=0

snap_ct() {
	awk '
	function ispriv(ip) {
		if (ip ~ /^192\.168\./) return 1
		if (ip ~ /^10\./) return 1
		if (ip ~ /^172\.(1[6-9]|2[0-9]|3[01])\./) return 1
		return 0
	}
	{
		split("", ip); split("", sport); split("", dport); split("", bytes)
		if ($3 != "tcp" && $3 != "udp") next
		dir = 0
		for (i = 1; i <= NF; i++) {
			t = $i
			if (substr(t, 1, 4) == "src=") { dir++; ip[dir] = substr(t, 5) }
			else if (substr(t, 1, 6) == "sport=") sport[dir] = substr(t, 7)
			else if (substr(t, 1, 6) == "dport=") dport[dir] = substr(t, 7)
			else if (substr(t, 1, 6) == "bytes=") bytes[dir] = substr(t, 7) + 0
		}
		if (!ip[1] || !ip[2] || sport[1] == "" || dport[1] == "") next
		if (ispriv(ip[1])) {
			print ip[1] "|" sport[1] ">" ip[2] "|" dport[1], bytes[1], bytes[2]
		} else if (ispriv(ip[2])) {
			print ip[2] "|" sport[2] ">" ip[1] "|" dport[2], bytes[2], bytes[1]
		}
	}' /proc/net/nf_conntrack 2>/dev/null
}

# ---- bind 快照："key bytes"（仅 IPv4；反向条目归一化为发起方视角）
snap_pb() {
	awk '
	function ispriv(ip) {
		if (ip ~ /^192\.168\./) return 1
		if (ip ~ /^10\./) return 1
		if (ip ~ /^172\.(1[6-9]|2[0-9]|3[01])\./) return 1
		return 0
	}
	{
		n = split($0, f, /[ \t]+/)
		src = ""; dst = ""; b = 0
		for (i = 1; i <= n; i++) {
			t = f[i]
			if (substr(t, 1, 5) == "orig=") {
				o = substr(t, 6)
				split(o, ends, "->")
				split(ends[1], s1, ":"); split(ends[2], s2, ":")
				src = s1[1]; sport = s1[2]
				dst = s2[1]; dport = s2[2]
			}
			else if (substr(t, 1, 6) == "bytes=") b = substr(t, 7) + 0
		}
		if (!src || !dst || sport == "" || dport == "") next
		if (ispriv(src)) print src "|" sport ">" dst "|" dport, b
		else if (ispriv(dst)) print dst "|" dport ">" src "|" sport, b
	}' /sys/kernel/debug/ppe0/bind /sys/kernel/debug/ppe1/bind 2>/dev/null
}

# ---- 融合：读 ct.prev pb.prev tot.prev ct.now pb.now
#      输出：第1行 JSON；第2+行 "ip tu td"（新累计状态）
fuse() {
	awk -v now="$1" -v pts="$2" '
	FILENAME == ARGV[1] { pu[$1] = $2 + 0; pd[$1] = $3 + 0; next }
	FILENAME == ARGV[2] { pbb[$1] = $2 + 0; next }
	FILENAME == ARGV[3] {
		if (NF >= 5) { GU[$1] = $2 + 0; GD[$1] = $3 + 0; DU[$1] = $4 + 0; DD[$1] = $5 + 0 }
		else if (NF == 3) { GU[$1] = $2 + 0; GD[$1] = $3 + 0; DU[$1] = $2 + 0; DD[$1] = $3 + 0 }
		next
	}
	FILENAME == ARGV[4] {
		key = $1
		match(key, /^[0-9.]+/)
		ip = substr(key, 1, RLENGTH)
		SEEN[ip] = 1
		if (key in pu) {
			du = ($2 + 0) - pu[key]; dd = ($3 + 0) - pd[key]
			if (du > 0) UP[ip] += du
			if (dd > 0) DOWN[ip] += dd
		}
		CU[key] = $2 + 0; CD[key] = $3 + 0
		next
	}
	FILENAME == ARGV[5] {
		key = $1
		match(key, /^[0-9.]+/)
		ip = substr(key, 1, RLENGTH)
		SEEN[ip] = 1
		if (key in pbb) {
			db = ($2 + 0) - pbb[key]
			if (db > 0) {
				tc = (key in CU ? CU[key] : 0) + (key in CD ? CD[key] : 0)
				r = (tc > 0 && key in CD) ? CD[key] / tc : 0.5
				DOWN[ip] += db * r
				UP[ip] += db * (1 - r)
			}
		}
		next
	}
	END {
		dt = now - pts
		if (dt < 1) dt = 1
		for (ip in GU) SEEN[ip] = 1
		printf "{\"ts\":%d", now
		body = ""
		for (ip in SEEN) {
			u = (ip in UP ? UP[ip] : 0); d = (ip in DOWN ? DOWN[ip] : 0)
			ngu = (ip in GU ? GU[ip] : 0) + u
			ngd = (ip in GD ? GD[ip] : 0) + d
			ndu = (ip in DU ? DU[ip] : 0) + u
			ndd = (ip in DD ? DD[ip] : 0) + d
			NGU[ip] = ngu; NGD[ip] = ngd; NDU[ip] = ndu; NDD[ip] = ndd
			seg = sprintf("\"%s\":{\"u\":%.0f,\"d\":%.0f,\"tu\":%.0f,\"td\":%.0f,\"gu\":%.0f,\"gd\":%.0f}", ip, u / dt, d / dt, ndu, ndd, ngu, ngd)
			body = body (body == "" ? "" : ",") seg
		}
		printf "%s}\n", (body == "" ? "" : "," body)
		for (ip in NGU) printf "%s %.0f %.0f %.0f %.0f\n", ip, NGU[ip], NGD[ip], NDU[ip], NDD[ip]
	}
	' "$D/ct.prev" "$D/pb.prev" "$D/tot.prev" "$D/ct.now" "$D/pb.now"
}

seed() {
	if [ -s "$D/tot.prev" ]; then
		n=$(awk 'NR==1{print NF; exit}' "$D/tot.prev" 2>/dev/null)
		if [ "$n" = "5" ]; then return 0; fi
		awk '{printf "%s %.0f %.0f %.0f %.0f\n", $1, $2, $3, $2, $3}' "$D/tot.prev" > "$D/tot.m" && mv "$D/tot.m" "$D/tot.prev"
		return 0
	fi
	if [ -s "$PERSIST" ]; then
		pday=$(sed -n '1s/^DAY //p' "$PERSIST")
		if [ "$pday" = "$TODAY" ]; then
			tail -n +2 "$PERSIST" > "$D/tot.prev"
		else
			tail -n +2 "$PERSIST" | awk '{printf "%s %.0f %.0f 0 0\n", $1, $2, $3}' > "$D/tot.prev"
		fi
	else
		: > "$D/tot.prev"
	fi
}

flush() {
	{ echo "DAY $TODAY"; cat "$D/tot.prev" 2>/dev/null; } > "$PERSIST.tmp" 2>/dev/null \
		&& mv "$PERSIST.tmp" "$PERSIST"
}

trap 'flush; exit 0' TERM INT
seed
touch "$D/ct.prev" "$D/pb.prev" 2>/dev/null

while :; do
	now=$(date +%s)
	snap_ct > $D/ct.now
	snap_pb > $D/pb.now
	pts=$(cat $D/ts 2>/dev/null || echo 0)
	fuse "$now" "$pts" > $D/out.all 2>/dev/null
	head -1 $D/out.all > "$TMP.tmp"
	mv "$TMP.tmp" "$TMP"
	chmod 644 "$TMP" 2>/dev/null
	tail -n +2 $D/out.all > $D/tot.m 2>/dev/null && mv $D/tot.m $D/tot.prev
	mv $D/ct.now $D/ct.prev
	mv $D/pb.now $D/pb.prev
	echo "$now" > $D/ts

	TODAY=$(date +%F)
	if [ "$TODAY" != "$LASTDAY" ]; then
		awk '{printf "%s %.0f %.0f 0 0\n", $1, $2, $3}' "$D/tot.prev" > "$D/tot.m" 2>/dev/null && mv "$D/tot.m" "$D/tot.prev"
		LASTDAY=$TODAY
		flush
	fi
	ROUNDS=$((ROUNDS+1))
	if [ $((ROUNDS % 300)) -eq 0 ]; then flush; fi
	sleep 2
done
