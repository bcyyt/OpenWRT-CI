-- adash.lua — LuCI controller: 低 CPU 状态监控仪表盘（luci-app-adash, QCB-ARGON 线专用）
-- 独立一级菜单「状态监控」；数据来自 /cgi-bin/adash（fork statusmon v4.49 低 CPU 改造版）
-- 与 vantage 线的 luci-app-statusmon / S20P 线的 statusmon-dash 互斥，永不共存

module("luci.controller.adash", package.seeall)

function index()
        entry({"admin", "adash"}, template("adash/status"), "状态监控", 5).dependent = false
end
