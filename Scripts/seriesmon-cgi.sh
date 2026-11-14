#!/bin/sh
# seriesmon — 仪表盘 24h 曲线数据端点（uhttpd CGI，nobody 身份）
# 转发 statusflow-worker 每 30s 写入的 /tmp/statusflow.d/series.jsonl（tmpfs，滚动 24h）
# 每行：{"t":<unix>,"c":<cpu%>,"d":<下行bps>,"u":<上行bps>}
echo "Content-Type: text/plain"
echo "Cache-Control: no-store"
echo ""

tail -n 2880 /tmp/statusflow.d/series.jsonl 2>/dev/null
exit 0
