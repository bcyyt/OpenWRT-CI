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
		ba0=0; bb0=0; ba1=0; bb1=0
        if [ -r /sys/kernel/debug/ppe0/entries ] || [ -r /sys/kernel/debug/ppe1/entries ]; then
                for p in /sys/kernel/debug/ppe0/entries /sys/kernel/debug/ppe1/entries; do
                        [ -r "$p" ] || continue
                        ent=$(cat "$p" 2>/dev/null)
                        if [ -n "$ent" ]; then
                                et=$(printf '%s\n' "$ent" | wc -l)
                                ea=$(printf '%s\n' "$ent" | grep -c 'IPv4')
                                eb=$(printf '%s\n' "$ent" | grep -c 'IPv6')
                        else
                                et=0; ea=0; eb=0
                        fi
                        case "$p" in
                                *ppe0*) t0=$et; a0=$ea; b0=$eb ;;
                                *ppe1*) t1=$et; a1=$ea; b1=$eb ;;
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
        elif [ -r /sys/kernel/debug/hnat/hnat_stats ]; then
                # 2026-11-19: S20P chasey 6.12 SDK mtkhnat 布局——hnat_stats 容量/绑定 + all_entry v4/v6 占用
                [ "$(cat /sys/kernel/debug/hnat/hook_toggle 2>/dev/null)" = "enabled" ] && hw=1
                hs=$(cat /sys/kernel/debug/hnat/hnat_stats 2>/dev/null)
                he=$(cat /sys/kernel/debug/hnat/all_entry 2>/dev/null)
                if [ -n "$hs" ]; then
                        t0=$(printf '%s\n' "$hs" | sed -n 's/^PPE0: entry num=\([0-9]*\).*/\1/p')
                        t1=$(printf '%s\n' "$hs" | sed -n 's/^PPE1: entry num=\([0-9]*\).*/\1/p')
                        bd0=$(printf '%s\n' "$hs" | sed -n 's/^PPE0: entry num=[0-9]*, BIND state num=\([0-9]*\).*/\1/p')
                        bd1=$(printf '%s\n' "$hs" | sed -n 's/^PPE1: entry num=[0-9]*, BIND state num=\([0-9]*\).*/\1/p')
                fi
                : ${bd0:=0}; : ${bd1:=0}
                if [ -n "$he" ]; then
                        a0=$(printf '%s\n' "$he" | grep -c 'ppe=0.*IPV4')
                        b0=$(printf '%s\n' "$he" | grep -c 'ppe=0.*IPV6')
                        a1=$(printf '%s\n' "$he" | grep -c 'ppe=1.*IPV4')
                        b1=$(printf '%s\n' "$he" | grep -c 'ppe=1.*IPV6')
		ba0=$(printf '%s\n' "$he" | grep -c 'ppe=0.*state=BIND.*IPV4')
		bb0=$(printf '%s\n' "$he" | grep -c 'ppe=0.*state=BIND.*IPV6')
		ba1=$(printf '%s\n' "$he" | grep -c 'ppe=1.*state=BIND.*IPV4')
		bb1=$(printf '%s\n' "$he" | grep -c 'ppe=1.*state=BIND.*IPV6')
                fi
        fi

        # CPU：与 LuCI 概览页同源（ubus luci.getCPUUsage = top -n1）
        cu=$(ubus call luci getCPUUsage 2>/dev/null | tr -d ' "' | sed -n 's/.*cpuusage:\([0-9]*\).*/\1/p')
        case "$cu" in ''|*[!0-9]*) cu=-1 ;; esac
        # 30秒级滚动均值（近6个样本），环与曲线统一口径
        if [ "$cu" -ge 0 ]; then
                printf '%s\n' "$cu" >> /tmp/statusppe-cpu.hist
                tail -6 /tmp/statusppe-cpu.hist > /tmp/statusppe-cpu.hist.tmp 2>/dev/null && mv -f /tmp/statusppe-cpu.hist.tmp /tmp/statusppe-cpu.hist
        fi
        cua=$(awk '{s+=$1;n++}END{if(n>0)printf "%d",s/n}' /tmp/statusppe-cpu.hist 2>/dev/null)
        case "$cua" in ''|*[!0-9]*) cua=-1 ;; esac

        now=$(date +%s)
        printf '%d %d %d\n' "$t" "$u" "$s" > "$ST"

        printf '{"hw":%d,"cpu":%d,"cpu_avg":%d,"usr":%d,"sys":%d,"ppe0":{"t":%d,"v4":%d,"v6":%d,"b":%d,"bv4":%d,"bv6":%d},"ppe1":{"t":%d,"v4":%d,"v6":%d,"b":%d,"bv4":%d,"bv6":%d},"ts":%d}\n' \
                "$hw" "$cu" "$cua" "$usr" "$sys" "$t0" "$a0" "$b0" "\$bd0" "\$ba0" "\$bb0" "\$t1" "$a1" "$b1" "\$bd1" "\$ba1" "\$bb1" "\$now" > "$TMP.tmp"
        mv "$TMP.tmp" "$TMP"
        chmod 644 "$TMP" 2>/dev/null

        sleep 5
done
