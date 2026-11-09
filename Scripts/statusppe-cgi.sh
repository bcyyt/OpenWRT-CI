#!/bin/sh
# statusppe — PPE 硬件表项占用数据接口（uhttpd CGI，nobody 身份）
# 直接转发 root 采样守护 /usr/lib/statusppe-worker.sh 写入的 /tmp/statusppe.json
echo "Content-Type: application/json"
echo ""

if [ -r /tmp/statusppe.json ]; then
	cat /tmp/statusppe.json
else
	printf '{"hw":0,"usr":0,"sys":0,"ppe0":{"t":0,"v4":0,"v6":0},"ppe1":{"t":0,"v4":0,"v6":0},"ts":0}\n'
fi
