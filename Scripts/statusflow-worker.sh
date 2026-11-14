#!/bin/sh
# statusflow-worker v5.5 — 每客户端上下行实时速率 + 今日/累计流量 + 24h CPU/WAN 曲线采样
#
# 数据源（每 2 秒差分）：
#   /proc/net/nf_conntrack — 每流 orig/reply 独立计数（精确双向）
#   首次见到的表项不计增量（防止长流历史字节跳变）
#
# v5.5 幽灵过滤（关键修复）：
#   MT7988 PPE 的 flowtable 统计回写路径存在缺陷——offloaded 流的 conntrack
#   bytes 会被周期性加上【MIB 累计全量】而非增量，流已结束后计数仍以恒定
#   步长持续虚增（实测：空闲期 WAN 0.6MB/60s 而 ct 账面 +1167MB）。
#   修复双层：
#     a) 幽灵检测：三轮差分比较（prev2→prev→now），差分>200KB 且两轮差分
#        相差<4% 判定幽灵，冻结该 key 的差分（输出 prev 值），key 记入
#        ghist；已记录 key 差分仍>200KB 且在记忆值 0.5~2 倍区间则持续冻结，
#        差分消失后自动移出恢复正常统计。
#     b) 接口钳制：每轮所有客户端 u/d 之和若超过 WAN 口+LAN 口实测差分的
#        1.3 倍，按比例整体缩放（物理上限保底，杜绝 2000× 级虚增）。
#
# 统计（持久化 /etc/statusflow/totals.state，每 10 分钟 + 停机/跨天时落盘）：
#   tu/td = 今日 上行/下行 累计；gu/gd = 总计 上行/下行（跨天 tu/td 归零，gu/gd 续算）
#
# 24h 曲线：/tmp/statusflow.d/series.jsonl（30s 节拍 CPU% + WAN 上下行 bps，
#           滚动 2880 点=24h，tmpfs 稳态零闪存写；存档 /etc/statusflow/series.save）
#
# 输出 /tmp/statusflow.json：
#   {"ts":N,"<ip>":{"u":<B/s>,"d":<B/s>,"tu":N,"td":N,"gu":N,"gd":N}}
# 注意：字节计数一律 %.0f 输出（busybox awk 的 %d 会 32 位饱和）

D=/tmp/statusflow.d
TMP=/tmp/statusflow.json
PD=/etc/statusflow
PERSIST=$PD/totals.state
GHIST=$D/ghist
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

# ---- 幽灵过滤（v5.5）：ct 快照差分的 PPE stats 污染剔除 ----
# 用法: deghost <prev2> <prev> <now>   （原地修正 now）
# 幽灵特征：offloaded 流的 ct.bytes 被内核 flowtable stats 以【恒定全量】
# 反复累加 → 连续差分几乎恒定。判定成立即冻结该 key（差分置 0）。
deghost() {
        [ -f "$GHIST" ] || : > "$GHIST"
        awk -v GHISTF="$GHIST" '
                FILENAME == ARGV[1] { b2[$1] = $2 + 0; c2[$1] = $3 + 0; next }
                FILENAME == ARGV[2] { b1[$1] = $2 + 0; c1[$1] = $3 + 0; next }
                FILENAME == ARGV[3] { b0[$1] = $2 + 0; c0[$1] = $3 + 0; order[++n] = $1; next }
                FILENAME == ARGV[4] { gv[$1] = $2 + 0; next }   # ghist: key 幽灵增量记忆
                END {
                        for (i = 1; i <= n; i++) {
                                k = order[i]
                                u2 = (k in b1) ? b0[k] - b1[k] : -1
                                d2 = (k in c1) ? c0[k] - c1[k] : -1
                                u1 = (k in b2 && k in b1) ? b1[k] - b2[k] : -1
                                d1 = (k in c2 && k in c1) ? c1[k] - c2[k] : -1
                                freeze = 0; ngv = 0
                                # 已记忆的幽灵 key：差分仍在记忆值 0.5~2 倍区间 → 持续冻结
                                if (k in gv) {
                                        if (d2 > 200000 && d2 > gv[k] * 0.5 && d2 < gv[k] * 2) { freeze = 1; ngv = d2 }
                                        else if (u2 > 200000 && u2 > gv[k] * 0.5 && u2 < gv[k] * 2) { freeze = 1; ngv = u2 }
                                }
                                # 新幽灵：三轮差分恒定（>200KB 且相差 <4%）
                                if (!freeze) {
                                        if (d1 > 200000 && d2 > 200000) {
                                                r = (d2 > d1) ? (d2 - d1) / d2 : (d1 - d2) / d1
                                                if (r < 0.04) { freeze = 1; ngv = d2 }
                                        }
                                        if (!freeze && u1 > 200000 && u2 > 200000) {
                                                r = (u2 > u1) ? (u2 - u1) / u2 : (u1 - u2) / u1
                                                if (r < 0.04) { freeze = 1; ngv = u2 }
                                        }
                                }
                                if (freeze) {
                                        newgv[k] = ngv
                                        ub = (k in b1) ? b1[k] : b0[k]
                                        db = (k in c1) ? c1[k] : c0[k]
                                } else {
                                        ub = b0[k]; db = c0[k]
                                }
                                printf "%s %.0f %.0f\n", k, ub, db
                        }
                        for (k in newgv) print k, newgv[k] > GHISTF ".new"
                }
        ' "$1" "$2" "$3" "$GHIST" > "$3.tmp" && mv "$3.tmp" "$3"
        if [ -f "$GHIST.new" ]; then mv "$GHIST.new" "$GHIST"; else : > "$GHIST"; fi
        return 0
}

# ---- 接口快照（钳制用）："wanrx wantx lanrx lantx" ----
snap_dev() {
        awk -F'[: ]+' '$2 == "pppoe-wan" { w1 = $3; w2 = $11 } $2 == "br-lan" { l1 = $3; l2 = $11 } END { printf "%.0f %.0f %.0f %.0f\n", w1+0, w2+0, l1+0, l2+0 }' /proc/net/dev 2>/dev/null
}

# ---- 接口钳制（v5.5）：原地缩放 ct.now 的本轮增量 ----
# 用法: clamp_ct <ct.prev> <ct.now> <dev.prev> <dev.now>
# Σ增量超过 WAN+LAN 口差分×1.3（+2MB 突发余量）时按比例缩放，
# 修正的是 ct.now 本身，fuse 的差分与累计列自动保持一致。
clamp_ct() {
        [ -s "$3" ] && [ -s "$4" ] || return 0
        read -r wr1 wt1 lr1 lt1 < "$3"
        read -r wr2 wt2 lr2 lt2 < "$4"
        maxd=$(( (wr2 - wr1) + (lr2 - lr1) + (lt2 - lt1) )); [ "$maxd" -lt 0 ] && maxd=0
        maxu=$(( (wt2 - wt1) + (lr2 - lr1) + (lt2 - lt1) )); [ "$maxu" -lt 0 ] && maxu=0
        maxd=$(( maxd * 13 / 10 + 2000000 ))
        maxu=$(( maxu * 13 / 10 + 2000000 ))
        awk -v MAXD="$maxd" -v MAXU="$maxu" '
                FILENAME == ARGV[1] { pu[$1] = $2 + 0; pd[$1] = $3 + 0; next }
                {
                        du = ($1 in pu) ? $2 - pu[$1] : 0
                        dd = ($1 in pd) ? $3 - pd[$1] : 0
                        if (du > 0) su += du
                        if (dd > 0) sd += dd
                        key[++n] = $1; up[n] = $2; dn[n] = $3
                        dua[n] = (du > 0 ? du : 0); dda[n] = (dd > 0 ? dd : 0)
                        next
                }
                END {
                        scale_u = (su > MAXU && su > 0) ? MAXU / su : 1
                        scale_d = (sd > MAXD && sd > 0) ? MAXD / sd : 1
                        for (i = 1; i <= n; i++)
                                printf "%s %.0f %.0f\n", key[i], up[i] - dua[i] * (1 - scale_u), dn[i] - dda[i] * (1 - scale_d)
                }
        ' "$1" "$2" > "$2.tmp" && mv "$2.tmp" "$2"
        return 0
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


# ── 24h 时序采样：CPU + WAN 吞吐（30s 节拍 → tmpfs，滚动 2880 行 ≈ 24h）──
SER="$D/series.jsonl"
SRSV="$PD/series.save"

sr_wan_if() {
        ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}'
}

sr_sample() {
        now=$1
        lt=$(cat "$D/ser.t" 2>/dev/null || echo 0)
        [ $((now - lt)) -ge 27 ] || return 0
        read -r _ u n sy id wa irq sq _rest < /proc/stat || return 0
        busy=$((u + n + sy + irq + sq))
        total=$((u + n + sy + id + wa + irq + sq))
        wif=$(sr_wan_if); [ -n "$wif" ] || wif="pppoe-wan"
        rxtx=$(awk -v IF="$wif" '$1==IF":"{print $2, $10}' /proc/net/dev 2>/dev/null)
        rx=${rxtx%% *}; tx=${rxtx##* }
        case "$rx" in ''|*[!0-9]*) rx=0;; esac
        case "$tx" in ''|*[!0-9]*) tx=0;; esac
        if [ -f "$D/ser.snap" ] && [ "$lt" -gt 0 ]; then
                read -r lb ltt lrx ltx < "$D/ser.snap" || { lb=$busy; ltt=$total; lrx=$rx; ltx=$tx; }
                [ $((total - ltt)) -gt 0 ] && [ $((now - lt)) -gt 0 ] && awk \
                        -v T="$now" -v L="$lt" -v B="$busy" -v TT="$total" -v LB="$lb" -v LTT="$ltt" \
                        -v R="$rx" -v LR="$lrx" -v X="$tx" -v LX="$ltx" 'BEGIN{
                                c = (B - LB) * 100 / (TT - LTT); if (!(c >= 0 && c <= 100)) c = 0;
                                d = (R >= LR) ? (R - LR) * 8 / (T - L) : 0;
                                u2 = (X >= LX) ? (X - LX) * 8 / (T - L) : 0;
                                printf "{\"t\":%.0f,\"c\":%.0f,\"d\":%.0f,\"u\":%.0f}\n", T, c, d, u2
                        }' >> "$SER"
        fi
        echo "$busy $total $rx $tx" > "$D/ser.snap"
        echo "$now" > "$D/ser.t"
        chmod 644 "$SER" 2>/dev/null || true
        lines=$(wc -l < "$SER" 2>/dev/null || echo 0)
        if [ "$lines" -gt 2920 ]; then
                tail -n 2880 "$SER" > "$SER.tmp" 2>/dev/null && mv "$SER.tmp" "$SER"
        fi
        return 0
}

sr_save() {
        [ -s "$SER" ] && cp "$SER" "$SRSV.tmp" 2>/dev/null && mv "$SRSV.tmp" "$SRSV"
        return 0
}

sr_restore() {
        [ -s "$SRSV" ] && cp "$SRSV" "$SER" 2>/dev/null
        return 0
}

trap 'flush; sr_save; exit 0' TERM INT
seed
sr_restore
touch "$D/ct.prev" "$D/ct.prev2" "$D/pb.prev" "$D/dev.prev" 2>/dev/null
: > "$GHIST" 2>/dev/null

while :; do
        now=$(date +%s)
        sr_sample "$now"
        snap_ct > $D/ct.now
        snap_pb > $D/pb.now
        snap_dev > $D/dev.now
        # 幽灵过滤 + 接口钳制（v5.5）：恒定差分流冻结；Σ增量超物理上限整体缩放
        [ -s "$D/ct.prev" ] && deghost "$D/ct.prev2" "$D/ct.prev" "$D/ct.now"
        clamp_ct "$D/ct.prev" "$D/ct.now" "$D/dev.prev" "$D/dev.now"
        pts=$(cat $D/ts 2>/dev/null || echo 0)
        fuse "$now" "$pts" > $D/out.all 2>/dev/null
        head -1 $D/out.all > "$TMP.tmp"
        mv "$TMP.tmp" "$TMP"
        chmod 644 "$TMP" 2>/dev/null
        tail -n +2 $D/out.all > $D/tot.m 2>/dev/null && mv $D/tot.m $D/tot.prev
        mv $D/ct.prev $D/ct.prev2 2>/dev/null
        mv $D/ct.now $D/ct.prev
        mv $D/pb.now $D/pb.prev
        mv $D/dev.now $D/dev.prev
        echo "$now" > $D/ts.prev
        echo "$now" > $D/ts

        TODAY=$(date +%F)
        if [ "$TODAY" != "$LASTDAY" ]; then
                awk '{printf "%s %.0f %.0f 0 0\n", $1, $2, $3}' "$D/tot.prev" > "$D/tot.m" 2>/dev/null && mv "$D/tot.m" "$D/tot.prev"
                LASTDAY=$TODAY
                flush
                sr_save
        fi
        ROUNDS=$((ROUNDS+1))
        if [ $((ROUNDS % 300)) -eq 0 ]; then flush; fi
        sleep 2
done
