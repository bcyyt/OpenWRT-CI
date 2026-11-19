-- statusmon.lua — LuCI controller: 状态监控仪表盘（luci-app-statusmon-dash, S20P-612 专用）
-- 独立一级菜单「状态监控」；页面数据来自包内自带的
-- /cgi-bin/statusmon（v4.49 同源后端）与 /cgi-bin/statusppe（PPE/CPU worker）
-- 与 618 线的 luci-app-statusmon（纯后端，Vantage 首页数据源）互斥，永不共存

module("luci.controller.statusmon", package.seeall)

function index()
	entry({"admin", "statusmon"}, template("statusmon/status"), "状态监控", 5).dependent = false
end
