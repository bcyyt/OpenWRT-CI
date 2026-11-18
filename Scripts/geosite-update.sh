#!/bin/sh
# geosite.dat 自动更新 - 数据源 Loyalsoldier/v2ray-rules-dat (每日22:04发布)
# v3 2026-11-18: 陈锁自愈(pid检测) + Bind轮询检查 + 双下载源
# 详见 OpenWRT-CI 仓库 TROUBLESHOOTING.md
DAT=/usr/share/v2ray/geosite.dat
LOG=/var/log/daed/daed.log
ULOG=/var/log/geosite-update.log
TMP=/tmp/geosite-new.dat
LOCK=/tmp/geosite-update.lock

# 并发锁(带陈锁自愈: 持锁进程已死则接管)
mkdir "$LOCK" 2>/dev/null || {
  OLD_PID=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -z "$OLD_PID" ] || ! kill -0 "$OLD_PID" 2>/dev/null; then
    rm -rf "$LOCK" && mkdir "$LOCK"
  else
    echo "$(date '+%F %T') SKIP run in progress (pid $OLD_PID)" >> "$ULOG"; exit 0
  fi
}
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT
log() { echo "$(date '+%F %T') $*" >> "$ULOG"; }

ok=0
for U in "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat" \
         "https://ghfast.top/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/latest/geosite.dat"; do
  rm -f "$TMP"
  curl -fsSL --retry 2 --connect-timeout 15 -o "$TMP" "$U" && { ok=1; break; }
done
if [ "$ok" != 1 ] || [ ! -s "$TMP" ]; then log "ERR download failed, keep current"; exit 1; fi

SIZE=$(wc -c < "$TMP")
if [ "$SIZE" -lt 5000000 ]; then log "ERR size=$SIZE abnormal, keep current"; rm -f "$TMP"; exit 1; fi

NEW=$(md5sum "$TMP" | cut -d' ' -f1)
OLD=$(md5sum "$DAT" | cut -d' ' -f1)
if [ "$NEW" = "$OLD" ]; then log "OK already latest $OLD"; rm -f "$TMP"; exit 0; fi

cp "$DAT" "$DAT.bak" || { log "ERR backup failed"; exit 1; }
cp "$TMP" "$DAT" && rm -f "$TMP"
/etc/init.d/daed restart >/dev/null 2>&1

# 重启后日志全新; Bind 出现 = 控制平面加载成功(含 dat 解析). 最多等45秒
i=0
while [ $i -lt 9 ]; do
  sleep 5
  if grep -q 'Bind to WAN' "$LOG" 2>/dev/null; then
    log "OK updated $OLD -> $NEW"
    exit 0
  fi
  i=$((i+1))
done
cp "$DAT.bak" "$DAT"
/etc/init.d/daed restart >/dev/null 2>&1
log "WARN new dat not loaded in 45s, rolled back to $OLD"
