'use strict';
'require view';
'require form';
/* ZTE Mesh 无线详情配置 — zte-wifi 守护（/usr/lib/zte-wifi.py）的 LuCI 前端。
   密码仅存本机 /etc/config/zte-wifi（UCI，root 可读），保存后守护 30s 内热加载。 */
return view.extend({
        title: function() { return _('ZTE Mesh 无线'); },

        render: function() {
                var m, s, o;

                m = new form.Map('zte-wifi', _('ZTE Mesh 无线详情'),
                        _('zte-wifi 守护通过中兴路由器本地 API 登录各 mesh 节点，采集无线客户端的频段与挂载节点，在仪表盘客户端列表显示徽标。保存后约一个采集周期内自动生效，无需重启。'));

                s = m.section(form.TypedSection, 'main', _('基本设置'));
                s.anonymous = true;

                o = s.option(form.Value, 'password', _('管理密码'),
                        _('中兴路由器 Web 管理密码（与浏览器登录节点管理页相同），仅保存在本机。'));
                o.password = true;
                o.rmempty = true;

                o = s.option(form.Value, 'interval', _('采集间隔（秒）'),
                        _('轮询各节点的周期，范围 10–3600，默认 30。'));
                o.datatype = 'and(uinteger, min(10), max(3600))';
                o.placeholder = '30';
                o.rmempty = true;

                s = m.section(form.GridSection, 'node', _('Mesh 节点'),
                        _('要采集的中兴 mesh 节点管理 IP；「主节点」会额外拉取 mesh 拓扑（节点名称与主/子角色）。'));
                s.addremove = true;
                s.anonymous = true;
                s.nodescriptions = true;

                o = s.option(form.Value, 'ip', _('IP 地址'));
                o.datatype = 'ipaddr';
                o.placeholder = '192.168.10.1';
                o.rmempty = false;

                o = s.option(form.Value, 'name', _('节点名称'),
                        _('显示在客户端徽标上的节点名，如「客厅AX5400」。'));
                o.placeholder = '客厅 AX5400';
                o.rmempty = true;

                o = s.option(form.Flag, 'topo', _('主节点（拉拓扑）'),
                        _('mesh 主控制器节点才需要勾选；只需一个。'));
                o.rmempty = true;

                return m.render();
        }
});
