#!/bin/sh
# statusppe-worker — root 常驻采样：PPE 硬件表项占用 + CPU USR/SYS 占用
# 由 /etc/init.d/statusppe 以 procd 启动，每 5 秒采样一次
# 输出 /tmp/statusppe.json（0644，uhttpd CGI 以 nobody 身份可读）
# 口径与 Luci 原生概览一致：
#   - 表项数 = /sys/kernel/debug/ppeN/entries 行数（硬件转发表全量，含未绑定表项）
#   - usr/sys = /proc/stat 5 秒差分（usr=user+nice，sys=system+irq+softirq）
# 结构：{"hw":1,"usr":2,"sys":0,"ppe0":{"t":40,"v4":40,"v6":0},"ppe1":{...},"ts":...}
ST=/tmp/statusppe.state
TMP=/tmp/statusppe.json

cpu_snap() { awk '/^cpu /{print $2+$3, $4+$7+$8, $2+$3+$4+$5+$6+$7+$8}' /proc/stat; }

while :; do
        hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw 2>/dev/null)
        [ "$hw" = "1" ] || hw=0

        # CPU 占用差分
        usr=0; sys=0
        set -- $(cpu_snap)
        u=$1; s=$2; t=$3
        if [ -s "$ST" ]; then
                read ptt pu ps < "$ST" 2>/dev/null
                if [ -n "$ptt" ] && [ -n "$pu" ] && [ -n "$ps" ]; then
                        dt=$((t - ptt)); du=$((u - pu)); ds=$((s - ps))
                        if [ "$dt" -gt 0 ] && [ "$du" -ge 0 ] && [ "$ds" -ge 0 ]; then
                                usr=$((du * 100 / dt)); sys=$((ds * 100 / dt))
                        fi
                fi
        fi

        # PPE 表项占用（entries 全量表；cat 一次后用户态计数，6次debugfs dump→2次）
        # 2026-11-19: 双布局适配——6.18 主线为 ppe0/ppe1 分目录；chasey-dev 6.12 为 mtk_ppe/entries 单文件
        t0=0; a0=0; b0=0; t1=0; a1=0; b1=0
        if [ -r /sys/kernel/debug/ppe0/entries ] || [ -r /sys/kernel/debug/ppe1/entries ]; then
                for p in /sys/kernel/debug/ppe0/entries /sys/kernel/debug/ppe1/entries; do
                        [ -r "$p" ] || continue
                        ent=$(cat "$p" 2>/dev/null)
                        if [ -n "$ent" ]; then
                                t=$(printf '%s\n' "$ent" | wc -l)
                                a=$(printf '%s\n' "$ent" | grep -c 'IPv4')
                                b=$(printf '%s\n' "$ent" | grep -c 'IPv6')
                        else
                                t=0; a=0; b=0
                        fi
                        case "$p" in
                                *ppe0*) t0=$t; a0=$a; b0=$b ;;
                                *ppe1*) t1=$t; a1=$a; b1=$b ;;
                        esac
                done
        elif [ -r /sys/kernel/debug/mtk_ppe/entries ]; then
                # 6.12 内部 debugfs：单文件全量表项，归入 ppe0 槽位；ip4/ip6 大小写不敏感兼容内部格式
                ent=$(cat /sys/kernel/debug/mtk_ppe/entries 2>/dev/null)
                if [ -n "$ent" ]; then
                        t0=$(printf '%s\n' "$ent" | wc -l)
                        a0=$(printf '%s\n' "$ent" | grep -ci 'ip4')
                        b0=$(printf '%s\n' "$ent" | grep -ci 'ip6')
                fi
        fi

        now=$(date +%s)
        printf '%d %d %d\n' "$t" "$u" "$s" > "$ST"

        printf '{"hw":%d,"usr":%d,"sys":%d,"ppe0":{"t":%d,"v4":%d,"v6":%d},"ppe1":{"t":%d,"v4":%d,"v6":%d},"ts":%d}\n' \
                "$hw" "$usr" "$sys" "$t0" "$a0" "$b0" "$t1" "$a1" "$b1" "$now" > "$TMP.tmp"
        mv "$TMP.tmp" "$TMP"
        chmod 644 "$TMP" 2>/dev/null

        sleep 5
done
