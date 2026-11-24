module("luci.controller.slatebox", package.seeall)

function index()
        if not nixio.fs.access("/www/cgi-bin/slatebox") then
                return
        end
        entry({"admin", "slatebox"}, template("slatebox/dash"), _("SlateBox 控制台"), 4).dependent = false
end
