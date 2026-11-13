#!/bin/sh
# statusflow — 每客户端实时流量接口（uhttpd CGI，nobody 身份）
# 转发 root 采样守护 /usr/lib/statusflow-worker.sh 写入的 /tmp/statusflow.json
# {"ts":<unix>,"<ip>":{"u":<B/s>,"d":<B/s>,"tu":<今日↑>,"td":<今日↓>,"gu":<累计↑>,"gd":<累计↓>}}
echo "Content-Type: application/json"
echo ""

if [ -r /tmp/statusflow.json ]; then
	cat /tmp/statusflow.json
else
	printf '{"ts":0}\n'
fi
