#!/bin/sh
# zteinfo — 输出中兴 mesh 无线客户端数据（/tmp/zte-wifi.json，zte-wifi 守护维护）
# 总开关：zte-wifi.main.enabled=0 时输出 disabled，仪表盘不再显示 ZTE 徽章

echo "Content-Type: application/json"
echo ""

if [ "$(uci -q get zte-wifi.main.enabled)" = "0" ]; then
	echo '{"ts":0,"c":{},"n":{},"disabled":true}'
	exit 0
fi

if [ -s /tmp/zte-wifi.json ]; then
	cat /tmp/zte-wifi.json
else
	echo '{"ts":0,"c":{},"n":{}}'
fi
