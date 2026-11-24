-- FC 仪表盘（仿 FanchmWrt）：数据源 /cgi-bin/adash
module("luci.controller.fcdash", package.seeall)

function index()
    if not nixio.fs.access("/usr/lib/lua/luci/view/fcdash/dash.htm") then
        return
    end
    entry({"admin", "fcdash"}, firstchild(), "FC 仪表盘", 5)
    entry({"admin", "fcdash", "main"}, template("fcdash/dash"), "总览", 1).leaf = true
end
