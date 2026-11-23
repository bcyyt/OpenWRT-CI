#!/bin/sh
# statusflow-worker v5.8 — 每客户端上下行实时速率 + 今日/累计流量 + 24h CPU/WAN 曲线采样
#
# v5.8（2026-11-23 降耗重构，统计口径与 v5.7 完全一致）：
#   tick 2s→5s；ROUNDS%300→%120（维持 10 分钟落盘节拍）；
#   deghost 幽灵判定下限 200KB→500KB/轮（随窗口等比，速率下限语义不变）；
#   snap_ct/deghost/clamp_ct/fuse 四趟合并为单趟 flow_pass——conntrack 原始表
#   解析 1 次、历史文件各读 1 次，冻结→钳制→融合全程内存内完成，
#   每 tick fork ~30→~13，conntrack 相关全表遍历 ~8 遍→~3 遍；
#   零散 cat 改内建 read。
#
# 数据源（每 5 秒差分）：
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
# v5.7 方向修正：幽灵把 ct orig/reply 记成对称（上下行 1:1 假象），
#   每客户端只取总量占比，上下行按 WAN 口真实 rx:tx 比例拆分。
#
# v5.6 总账封顶（治本）：
#   PPE 幽灵步长不稳定（间歇回写）时 a) 抓不全、b) 的 2MB/轮余量也挡不住
#   中速幽灵（实测单客户端今日虚增 20GB，而 WAN 口当日真实仅 1.8GB）。
#   改为：每客户端按 ct 占比分摊 WAN 口（pppoe-wan）rx/tx 真实差分，
#   Σ每客户端 ≡ WAN 实测——总账封死，幽灵只能吃份额不能超总账。
#   注：deghost 阈值保持 v5.5（200KB/轮、4%、0.5~2）——收紧会误杀
#   稳定速率的正常流（差分恒定本就是常态流特征），占比全冻结成 0。
#   幽灵的残余稀释由总账封顶兜住，无需再收紧。
#   升级首启清零旧账本（历史虚高不作数）。
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

# ---- 接口快照（钳制用）："wanrx wantx lanrx lantx" ----
snap_dev() {
        # v5.6 修复：默认空格分隔，$1=iface:（剥掉尾冒号）、$2=rx_bytes、$10=tx_bytes。
        awk '{ i = $1; sub(/:$/, "", i); if (i == "pppoe-wan") { w1 = $2; w2 = $10 } else if (i == "br-lan") { l1 = $2; l2 = $10 } } END { printf "%.0f %.0f %.0f %.0f\n", w1+0, w2+0, l1+0, l2+0 }' /proc/net/dev 2>/dev/null
}

# ---- 单趟融合（v5.8）：snap_ct + deghost + clamp_ct + fuse 合并 ----
# 用法: flow_pass <ct.prev2> <ct.prev> <pb.prev> <tot.prev> <pb.now> <dev.prev> <ghist> -v ...
# stdout = out.all（首行 JSON + tot 行）；写 $D/ct.now.new 与 $GHIST.new
# 内核接口只解析一次（/proc/net/nf_conntrack），其余全部内存内完成。
flow_pass() {
        awk -v now="$now" -v pts="$pts" -v WRXD="$WRXD" -v WTXD="$WTXD" \
                -v MAXD="$maxd" -v MAXU="$maxu" -v CTF="$D/ct.now.new" -v GHISTF="$GHIST" '
        function ispriv(ip) {
                if (ip ~ /^192\.168\./) return 1
                if (ip ~ /^10\./) return 1
                if (ip ~ /^172\.(1[6-9]|2[0-9]|3[01])\./) return 1
                return 0
        }
        FILENAME == ARGV[1] { b2[$1] = $2 + 0; c2[$1] = $3 + 0; next }        # ct.prev2
        FILENAME == ARGV[2] { b1[$1] = $2 + 0; c1[$1] = $3 + 0; next }        # ct.prev
        FILENAME == ARGV[3] { pbb[$1] = $2 + 0; next }                        # pb.prev
        FILENAME == ARGV[4] {                                                 # tot.prev
                if (NF >= 5) { GU[$1] = $2 + 0; GD[$1] = $3 + 0; DU[$1] = $4 + 0; DD[$1] = $5 + 0 }
                else if (NF == 3) { GU[$1] = $2 + 0; GD[$1] = $3 + 0; DU[$1] = $2 + 0; DD[$1] = $3 + 0 }
                next
        }
        FILENAME == ARGV[5] { pbnow[$1] = $2 + 0; next }                      # pb.now
        FILENAME == ARGV[6] { wr1 = $1 + 0; wt1 = $2 + 0; lr1 = $3 + 0; lt1 = $4 + 0; next }  # dev.prev
        FILENAME == ARGV[7] { gv[$1] = $2 + 0; next }                         # ghist
        FILENAME == ARGV[8] {                                                 # /proc/net/nf_conntrack
                split("", cip); split("", sport); split("", dport); split("", bytes); dir = 0
                if ($3 != "tcp" && $3 != "udp") next
                for (i = 1; i <= NF; i++) {
                        t = $i
                        if (substr(t, 1, 4) == "src=") { dir++; cip[dir] = substr(t, 5) }
                        else if (substr(t, 1, 6) == "sport=") sport[dir] = substr(t, 7)
                        else if (substr(t, 1, 6) == "dport=") dport[dir] = substr(t, 7)
                        else if (substr(t, 1, 6) == "bytes=") bytes[dir] = substr(t, 7) + 0
                }
                if (!cip[1] || !cip[2] || sport[1] == "" || dport[1] == "") next
                if (ispriv(cip[1])) { k = cip[1] "|" sport[1] ">" cip[2] "|" dport[1]; b0[k] = bytes[1]; c0[k] = bytes[2] }
                else if (ispriv(cip[2])) { k = cip[2] "|" sport[2] ">" cip[1] "|" dport[2]; b0[k] = bytes[2]; c0[k] = bytes[1] }
                else next
                if (!(k in seen0)) { order[++n] = k; seen0[k] = 1 }
                match(k, /^[0-9.]+/)
                SEEN[substr(k, 1, RLENGTH)] = 1
        }
        END {
                dt = now - pts; if (dt < 1) dt = 1
                # ① 幽灵冻结（v5.5 语义；窗口 5s → 判定下限 500KB/轮）
                for (i = 1; i <= n; i++) {
                        k = order[i]
                        u2 = (k in b1) ? b0[k] - b1[k] : -1
                        d2 = (k in c1) ? c0[k] - c1[k] : -1
                        u1 = (k in b2 && k in b1) ? b1[k] - b2[k] : -1
                        d1 = (k in c2 && k in c1) ? c1[k] - c2[k] : -1
                        freeze = 0; ngv = 0
                        if (k in gv) {
                                if (d2 > 500000 && d2 > gv[k] * 0.5 && d2 < gv[k] * 2) { freeze = 1; ngv = d2 }
                                else if (u2 > 500000 && u2 > gv[k] * 0.5 && u2 < gv[k] * 2) { freeze = 1; ngv = u2 }
                        }
                        if (!freeze) {
                                if (d1 > 500000 && d2 > 500000) {
                                        r = (d2 > d1) ? (d2 - d1) / d2 : (d1 - d2) / d1
                                        if (r < 0.04) { freeze = 1; ngv = d2 }
                                }
                                if (!freeze && u1 > 500000 && u2 > 500000) {
                                        r = (u2 > u1) ? (u2 - u1) / u2 : (u1 - u2) / u1
                                        if (r < 0.04) { freeze = 1; ngv = u2 }
                                }
                        }
                        if (freeze) { newgv[k] = ngv; eb[k] = (k in b1) ? b1[k] : b0[k]; ed[k] = (k in c1) ? c1[k] : c0[k] }
                        else { eb[k] = b0[k]; ed[k] = c0[k] }
                }
                # ② 接口钳制（v5.5 语义）：Σ增量超 WAN+LAN 实测 ×1.3 + 2MB 按比例缩放
                su = 0; sd = 0
                for (i = 1; i <= n; i++) {
                        k = order[i]
                        du = (k in b1) ? eb[k] - b1[k] : 0
                        dd = (k in c1) ? ed[k] - c1[k] : 0
                        if (du > 0) su += du
                        if (dd > 0) sd += dd
                        dua[i] = (du > 0 ? du : 0); dda[i] = (dd > 0 ? dd : 0)
                }
                scale_u = (su > MAXU && su > 0) ? MAXU / su : 1
                scale_d = (sd > MAXD && sd > 0) ? MAXD / sd : 1
                print "" > CTF
                for (i = 1; i <= n; i++) {
                        k = order[i]
                        eb[k] -= dua[i] * (1 - scale_u)
                        ed[k] -= dda[i] * (1 - scale_d)
                        printf "%s %.0f %.0f\n", k, eb[k], ed[k] > CTF
                }
                close(CTF)
                # ③ 融合（v5.6/v5.7 语义）：ct/bind 增量按 WAN 口真实差分分摊
                for (i = 1; i <= n; i++) {
                        k = order[i]
                        match(k, /^[0-9.]+/); ipk = substr(k, 1, RLENGTH)
                        du = eb[k] - b1[k]; dd = ed[k] - c1[k]
                        if (du > 0) { UP[ipk] += du; SU += du }
                        if (dd > 0) { DOWN[ipk] += dd; SD += dd }
                        CU[k] = eb[k]; CD[k] = ed[k]
                }
                for (k in pbnow) {
                        match(k, /^[0-9.]+/); ipk = substr(k, 1, RLENGTH)
                        SEEN[ipk] = 1
                        if (k in pbb) {
                                db = pbnow[k] - pbb[k]
                                if (db > 0) {
                                        tc = (k in CU ? CU[k] : 0) + (k in CD ? CD[k] : 0)
                                        r = (tc > 0 && k in CD) ? CD[k] / tc : 0.5
                                        DOWN[ipk] += db * r
                                        UP[ipk] += db * (1 - r)
                                }
                        }
                }
                TOT = SU + SD
                if (TOT > 0) { wu = WTXD / TOT; wd = WRXD / TOT } else { wu = 0; wd = 0 }
                for (ip in GU) SEEN[ip] = 1
                printf "{\"ts\":%d", now
                body = ""
                for (ip in SEEN) {
                        if (TOT > 0) {
                                sh = ((ip in UP ? UP[ip] : 0) + (ip in DOWN ? DOWN[ip] : 0)) / TOT
                                u = wu * sh * TOT; d = wd * sh * TOT
                        } else { u = 0; d = 0 }
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
                for (k in newgv) print k, newgv[k] > GHISTF ".new"
        }
        ' "$1" "$2" "$3" "$4" "$5" "$6" "$7" /proc/net/nf_conntrack 2>/dev/null
        return 0
}

seed() {
        # v5.6：升级首启清零（旧账本今日/总计含幽灵虚高，不作数）。
        # 必须连 PERSIST 头一起重写为 VER 5.6，否则后面的 else 恢复分支
        # 会立即从旧 PERSIST 把虚高数据 tail 回 tot.prev（清零失效）。
        if [ -s "$PERSIST" ] && ! head -1 "$PERSIST" 2>/dev/null | grep -q "^VER 5.6"; then
                { echo "VER 5.6"; echo "DAY $(date +%F)"; } > "$PERSIST"
                : > "$D/tot.prev"
        fi
        if [ -s "$D/tot.prev" ]; then
                n=$(awk 'NR==1{print NF; exit}' "$D/tot.prev" 2>/dev/null)
                if [ "$n" = "5" ]; then return 0; fi
                awk '{printf "%s %.0f %.0f %.0f %.0f\n", $1, $2, $3, $2, $3}' "$D/tot.prev" > "$D/tot.m" && mv "$D/tot.m" "$D/tot.prev"
                return 0
        fi
        if [ -s "$PERSIST" ]; then
                pday=$(sed -n '1s/^DAY //p' "$PERSIST")
                if [ "$pday" = "$TODAY" ]; then
                        tail -n +3 "$PERSIST" > "$D/tot.prev"
                else
                        tail -n +3 "$PERSIST" | awk '{printf "%s %.0f %.0f 0 0\n", $1, $2, $3}' > "$D/tot.prev"
                fi
        else
                : > "$D/tot.prev"
        fi
}

flush() {
        { echo "VER 5.6"; echo "DAY $TODAY"; cat "$D/tot.prev" 2>/dev/null; } > "$PERSIST.tmp" 2>/dev/null \
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
        read -r lt _ < "$D/ser.t" 2>/dev/null || lt=0
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
        snap_pb > $D/pb.now
        snap_dev > $D/dev.now
        read -r pts _ < "$D/ts" 2>/dev/null || pts=0
        read -r wr1 wt1 lr1 lt1 < "$D/dev.prev" 2>/dev/null || { wr1=0; wt1=0; lr1=0; lt1=0; }
        read -r wr2 wt2 lr2 lt2 < "$D/dev.now" 2>/dev/null || { wr2=0; wt2=0; lr2=0; lt2=0; }
        # 首轮/坏快照（prev 全 0）不计增量：否则 WAN 开机累计会被当成一轮
        # 增量全额灌给当时占比最高的客户端（v5.7 首启事故：.160 独得 1.9GB）
        if [ "$wr1" = "0" ] && [ "$wt1" = "0" ]; then
                WRXD=0; WTXD=0
        else
                WRXD=$(( wr2 - wr1 )); [ $WRXD -lt 0 ] && WRXD=0
                WTXD=$(( wt2 - wt1 )); [ $WTXD -lt 0 ] && WTXD=0
        fi
        # 钳制上限（v5.5 语义）：WAN+LAN 差分 ×1.3 + 2MB 突发余量
        maxd=$(( (wr2 - wr1) + (lr2 - lr1) + (lt2 - lt1) )); [ $maxd -lt 0 ] && maxd=0
        maxu=$(( (wt2 - wt1) + (lr2 - lr1) + (lt2 - lt1) )); [ $maxu -lt 0 ] && maxu=0
        maxd=$(( maxd * 13 / 10 + 2000000 ))
        maxu=$(( maxu * 13 / 10 + 2000000 ))
        # v5.8 单趟融合：解析+冻结+钳制+融合一次完成（原 4 个 awk → 1 个）
        : > "$D/ct.now.new"
        flow_pass "$D/ct.prev2" "$D/ct.prev" "$D/pb.prev" "$D/tot.prev" "$D/pb.now" "$D/dev.prev" "$GHIST" \
                > $D/out.all 2>/dev/null
        mv "$D/ct.prev" "$D/ct.prev2" 2>/dev/null
        mv "$D/ct.now.new" "$D/ct.prev" 2>/dev/null
        if [ -f "$GHIST.new" ]; then mv "$GHIST.new" "$GHIST"; else : > "$GHIST"; fi
        head -1 $D/out.all > "$TMP.tmp"
        mv "$TMP.tmp" "$TMP"
        chmod 644 "$TMP" 2>/dev/null
        tail -n +2 $D/out.all > $D/tot.m 2>/dev/null && mv $D/tot.m $D/tot.prev
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
        if [ $((ROUNDS % 120)) -eq 0 ]; then flush; fi
        sleep 5
done
