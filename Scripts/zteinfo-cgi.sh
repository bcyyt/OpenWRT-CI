#!/bin/sh
# zteinfo — 输出中兴 mesh 无线客户端数据（/tmp/zte-wifi.json，zte-wifi 守护维护）

echo "Content-Type: application/json"
echo ""

if [ -s /tmp/zte-wifi.json ]; then
	cat /tmp/zte-wifi.json
else
	echo '{"ts":0,"c":{},"n":{}}'
fi
