#!/bin/sh
# statusppe — PPE 硬件 offload 占用数据接口（uhttpd CGI，nobody 身份）
# 数据来自 root 采样守护 /usr/lib/statusppe-worker.sh 写入的 /tmp/statusppe.json
echo "Content-Type: application/json"
echo ""

hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw 2>/dev/null)
[ "$hw" = "1" ] || hw=0

if [ -r /tmp/statusppe.json ]; then
	f=$(grep -o '"flows":[0-9]*' /tmp/statusppe.json 2>/dev/null | cut -d: -f2)
	pp=$(grep -o '"pps":[0-9]*' /tmp/statusppe.json 2>/dev/null | cut -d: -f2)
	[ -n "$f" ] || f=0
	[ -n "$pp" ] || pp=0
	printf '{"ppe":{"flows":%d,"pps":%d,"hw":%s}}' "$f" "$pp" "$hw"
else
	printf '{"ppe":{"flows":0,"pps":null,"hw":%s}}' "$hw"
fi
