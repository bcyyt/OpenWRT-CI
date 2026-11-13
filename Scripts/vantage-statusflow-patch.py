#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# statusflow → Vantage 仪表盘注入（由 Scripts/Handles.sh 在编译期调用）
# 用法：vantage-statusflow-patch.py <overview.js> <app.css>
#
# 前端（配合 root 守护 /usr/lib/statusflow-worker.sh + nobody CGI /www/cgi-bin/statusflow）：
#   1) 每客户端实时双向速率（conntrack orig/reply + PPE bind 融合，共享端口也按 IP 拆分）
#      —— flowRate() 优先于 portRate()，title 注明「含硬件卸载流量」
#   2) 卡片 Live 区新增「今日 ↓x ↑y」（statFmt/flowStats，数据来自 worker 的 tu/td 字段）
#   3) 客户端详情抽屉新增「今日流量 / 累计流量」两行（flowStatKv）
#   4) 客户端列表默认按 IPv4 升序固定排列（ipValue + sorts 默认 ip）
#   5) 客户端列表分页：每页 10 条，翻页控件在列表标题右侧；过滤/切视图回第 1 页，
#      数据轮询刷新不跳页
#   6) 移动端 CSS：解除 vt-live-split 隐藏（手机也显示双向拆分）
import re, sys

def patch(src, pattern, repl, what, count=1, flags=0):
    new, n = re.subn(pattern, repl, src, count=count, flags=flags)
    if n != count:
        print(f'statusflow: anchor {what!r} matched {n} times (expect {count})', file=sys.stderr)
        sys.exit(1)
    return new

# ---------- overview.js ----------
ov_path, css_path = sys.argv[1], sys.argv[2]
ov = open(ov_path, encoding='utf-8').read()

if 'initFlow' in ov:
    print('vantage-statusflow: already patched, skip')
    sys.exit(0)

# 1) 挂载点：轮询注册后启动 initFlow（3s 拉取 /cgi-bin/statusflow）
ov = patch(ov, r"(\t\tpoll\.add\(L\.bind\(this\.refresh, this\), POLL_S\);)",
    r"\1\n\t\tthis.initFlow();",
    'poll.add refresh')

# 2) 新方法块（插在 sortValue 前）
methods = '''
        /* statusflow: per-IP live rates from /cgi-bin/statusflow, sampled by the
           statusflow procd daemon (conntrack orig/reply + PPE bind fusion).
           Takes precedence over the port rate, so clients on a shared port
           (a switch behind one LAN socket) still show their own traffic. */
        flowRate: function(c) {
                var ips = c && c.ips || [], fl = this.st.flow || {}, best = null;
                for (var i = 0; i < ips.length; i++) {
                        var f = fl[ips[i]];
                        if (f && f.u + f.d > 0 && (!best || f.u + f.d > best.rx + best.tx))
                                best = { rx: f.u, tx: f.d, flow: true };
                }
                return best;
        },

        /* statusflow: plain byte formatter for day/total counters (1024-based) */
        statFmt: function(n) {
                n = n || 0;
                var u = [ 'B', 'KB', 'MB', 'GB', 'TB' ], i = 0;
                while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
                return String(i === 0 ? Math.round(n) : n.toFixed(1)) + ' ' + u[i];
        },

        /* statusflow: sum today/total counters over a client's addresses */
        flowStats: function(c) {
                var ips = c && c.ips || [], fl = this.st.flow || {}, t = { du: 0, dd: 0, gu: 0, gd: 0 };
                for (var i = 0; i < ips.length; i++) {
                        var f = fl[ips[i]];
                        if (f) { t.du += f.tu || 0; t.dd += f.td || 0; t.gu += f.gu || 0; t.gd += f.gd || 0; }
                }
                return t;
        },

        /* statusflow: today/total traffic rows for the client drawer */
        flowStatKv: function(c) {
                var s = this.flowStats(c);
                if (!s || (!s.du && !s.dd && !s.gu && !s.gd)) return '';
                return kv('今日流量', E('div', {}, [
                        E('div', { 'class': 'vt-tn' }, [ '今日 ↓ ' + this.statFmt(s.dd) + ' · ↑ ' + this.statFmt(s.du) ]),
                        E('div', { 'class': 'vt-tn' }, [ '累计 ↓ ' + this.statFmt(s.gd) + ' · ↑ ' + this.statFmt(s.gu) ])
                ]), true);
        },

        /* statusflow: numeric IPv4 value, the default client list order
           (clients stay put instead of jumping around by live rate) */
        ipValue: function(c) {
                var ips = c && c.ips || [];
                for (var i = 0; i < ips.length; i++) {
                        var m = String(ips[i]).split('.');
                        if (m.length === 4 && m.every(function(x) { return /^\\d+$/.test(x) && +x < 256; }))
                                return +m[0] * 16777216 + +m[1] * 65536 + +m[2] * 256 + +m[3];
                }
                return 4294967295;
        },

        /* statusflow: poll the per-client flow JSON every 3s, rerender on change */
        initFlow: function() {
                var self = this;
                function load() {
                        fetch('/cgi-bin/statusflow', { cache: 'no-store' })
                                .then(function(r) { return r.json(); })
                                .then(function(d) {
                                        if (!d || !d.ts) return;
                                        var now = Object.create(null), chg = false;
                                        Object.keys(d).forEach(function(ip) {
                                                if (ip === 'ts') return;
                                                now[ip] = d[ip];
                                                var o = self.st.flow && self.st.flow[ip];
                                                if (!o || o.u !== d[ip].u || o.d !== d[ip].d || o.tu !== d[ip].tu || o.td !== d[ip].td) chg = true;
                                        });
                                        self.st.flow = now;
                                        if (chg) self.rerender();
                                })
                                .catch(function() {});
                }
                load();
                setInterval(load, 3000);
        },

        sortValue: function'''
# 2) 新方法块（插在 sortValue 前；固定文本锚点，避开 re 模板转义问题）
ANCHOR_SORT = '\n\tsortValue: function(c, key) {'
if ov.count(ANCHOR_SORT) != 1:
    print('statusflow: anchor sortValue head not unique', file=sys.stderr)
    sys.exit(1)
ov = ov.replace(ANCHOR_SORT, '\n' + methods + '(c, key) {', 1)

# 3) sortValue：wired 速率优先取 flowRate；switch 增加 ip 键
ov = patch(ov, r"(\t\tvar r = typeof c\.port === 'string' \? )this\.portRate\(c\)( : this\.st\.staRates\[c\.mac\];)",
    r"\1(this.flowRate(c) || this.portRate(c))\2",
    'sortValue r')
ov = patch(ov, r"(\t\tswitch \(key\) \{\n)(\t\tcase 'name':)",
    r"\1\t\tcase 'ip': return this.ipValue(c);\n\2",
    'switch ip case')

# 4) 默认排序 ip 升序 + 分页状态
ov = patch(ov, r"sorts: \{ wifi: \{ key: 'live', dir: -1 \}, wired: \{ key: 'seen', dir: 1 \} \}(, kind: 'wifi', filter: '', chip: 'all', drawer: null, editing: null, hover: null) \};",
    r"sorts: { wifi: { key: 'ip', dir: 1 }, wired: { key: 'ip', dir: 1 } }\1, page: 1 };",
    'ui sorts')

# 5) maxRate 统计同源
ov = patch(ov, r"(all\.forEach\(function\(c\) \{ var r = wired \? )self\.portRate\(c\)( : st\.staRates\[c\.mac\];)",
    r"\1(self.flowRate(c) || self.portRate(c))\2",
    'maxRate loop')

# 6) 分页切片（每页 10 条，按 IP 升序的全量切页）
ov = patch(ov, r"(\t\tvar keep = new Set\(\), at = 0;\n\t\tthis\.rowSig = this\.rowSig \|\| new Map\(\);\n\t\t)(list\.concat\(gone\)\.forEach)",
    r"\1var FULL = list.concat(gone), PS = 10, PAGES = Math.max(1, Math.ceil(FULL.length / PS));\n"
    r"\t\tif (ui.page > PAGES) ui.page = PAGES;\n"
    r"\t\tif (ui.page < 1) ui.page = 1;\n"
    r"\t\tvar VIEW = FULL.slice((ui.page - 1) * PS, ui.page * PS);\n"
    r"\t\tVIEW.forEach",
    'pagination slice')

# 7) 计数行后渲染翻页控件
ov = patch(ov, r"(\t\tel\.count\.hidden = both && list\.length === total;\n)",
    r"\1"
    r"\t\tif (PAGES > 1) {\n"
    r"\t\t\tdom.content(el.pager, [\n"
    r"\t\t\t\tE('button', { 'type': 'button', 'class': 'vt-btn vt-btn-ghost', 'aria-label': _('Previous page'), 'click': function() { if (ui.page > 1) { ui.page--; self.paintClients(); } } }, [ '‹' ]),\n"
    r"\t\t\t\tE('span', { 'class': 'vt-tn' }, [ ui.page + ' / ' + PAGES ]),\n"
    r"\t\t\t\tE('button', { 'type': 'button', 'class': 'vt-btn vt-btn-ghost', 'aria-label': _('Next page'), 'click': function() { if (ui.page < PAGES) { ui.page++; self.paintClients(); } } }, [ '›' ])\n"
    r"\t\t\t]);\n"
    r"\t\t}\n"
    r"\t\telse {\n"
    r"\t\t\tdom.content(el.pager, []);\n"
    r"\t\t}\n",
    'pager render')

# 8) el.pager 构建 + 挂进列表标题
ov = patch(ov, r"(\t\tel\.count = E\('span', \{ 'class': 'vt-count vt-tn' \}\);\n)",
    r"\1\t\tel.pager = E('span', { 'class': 'vt-pager' });\n",
    'el.pager create')
ov = patch(ov, r"tileHead\('users', _\('Clients'\), \[ el\.kinds, el\.count \]\),",
    r"tileHead('users', _('Clients'), [ el.kinds, el.count, el.pager ]),",
    'tileHead children')

# 9) 过滤/切视图回第 1 页
ov = patch(ov, r"(\tpickClients: function\(\) \{\n\t\tif \(this\.held\) delete this\.held\.clients;\n)",
    r"\1\t\tthis.ui.page = 1;\n",
    'pickClients reset')

# 10) wiredCells：速率优先 flowRate + 今日计数
ov = patch(ov, r"(\twiredCells: function\(c, maxRate\) \{\n\t\tvar r = )this\.portRate\(c\)(, total = r \? r\.rx \+ r\.tx : 0;\n)",
    r"\1(this.flowRate(c) || this.portRate(c))\2\t\tvar stt = this.flowStats(c);\n",
    'wiredCells head')

# 11) wired live 单元格：共享端口有 per-IP 数据也显示；title 注明含硬件卸载；追加今日行
ov = patch(ov, r"(E\('td', \{ 'class': 'vt-td-live', 'data-title': _\('Live'\) \}, c\.shared) \? \[",
    r"\1 && !r ? [",
    'wired shared branch')
ov = patch(ov,
    r"(E\('span', \{ 'class': 'vt-live-split vt-tn', 'title': r \? )(_\('To device %s, from device %s'\)\.format\(fmt\.bits\(r\.tx\), fmt\.bits\(r\.rx\)\))( : '' \}, \[ r \? fmt\.rates\(r\.tx, r\.rx\) : '' \]\))(\n\t+\]\)\n\t+\]\),\n\t+E\('td', \{ 'class': ')(vt-td-seen)",
    r"\1(r.flow ? _('To device %s, from device %s (incl. hardware offloaded traffic)').format(fmt.bits(r.tx), fmt.bits(r.rx)) : \2)\3,\n"
    r"\t\t\t\t\tE('span', { 'class': 'vt-live-day vt-tn' }, [ stt && (stt.dd || stt.du) ? '今日 ↓' + this.statFmt(stt.dd) + ' ↑' + this.statFmt(stt.du) : '' ])"
    r"\4\5",
    'wired live cell')

# 12) clientCells：今日计数
ov = patch(ov, r"(\tclientCells: function\(c, maxRate\) \{\n\t\tvar st = this\.st, r = c\.gone \? null : st\.staRates\[c\.mac\];\n\t\tvar total = r \? r\.rx \+ r\.tx : 0;\n)",
    r"\1\t\tvar stt = this.flowStats(c);\n",
    'clientCells head')

# 13) wifi live 单元格：追加今日行
ov = patch(ov,
    r"(E\('span', \{ 'class': 'vt-live-split vt-tn', 'title': r \? _\('To device %s, from device %s'\)\.format\(fmt\.bits\(r\.tx\), fmt\.bits\(r\.rx\)\) : '' \}, \[ r \? fmt\.rates\(r\.tx, r\.rx\) : '' \]\))(\n\t+\]\)\n\t+\]\),\n\t+E\('td', \{ 'class': ')(vt-td-exp)",
    r"\1,\n"
    r"\t\t\t\t\tE('span', { 'class': 'vt-live-day vt-tn' }, [ stt && (stt.dd || stt.du) ? '今日 ↓' + this.statFmt(stt.dd) + ' ↑' + this.statFmt(stt.du) : '' ])"
    r"\2\3",
    'wifi live cell')

# 14) drawerWired：速率优先 flowRate；Traffic 行后加统计
ov = patch(ov, r"(\t\tvar self = this, r = )this\.portRate\(c\)(, shared = c\.shared \? this\.st\.devRates\[c\.port\] : null;)",
    r"\1(this.flowRate(c) || this.portRate(c))\2",
    'drawerWired head')
ov = patch(ov, r"(\] : r \?'↓ ' \+ fmt\.bits\(r\.tx\) \+ ' · ↑ ' \+ fmt\.bits\(r\.rx\) : _\('measuring'\)\),\n)(\t+kv\(_\('Network'\),)",
    r"\1\t\t\t\tthis.flowStatKv(c),\n\2",
    'drawerWired stats kv')

# 15) drawerClient：Last activity 行后加统计
ov = patch(ov, r"(kv\(_\('Last activity', 'vantage'\), c\.inactive == null \|\| c\.gone \? fmt\.DASH : fmt\.ago\(c\.inactive\)\),\n)(\t+kv\(_\('Seen since'\),)",
    r"\1\t\t\t\tthis.flowStatKv(c),\n\2",
    'drawerClient stats kv')

open(ov_path, 'w', encoding='utf-8').write(ov)
print(f'vantage-statusflow: overview.js patched ({len(ov)} bytes)')

# ---------- app.css ----------
css = open(css_path, encoding='utf-8').read()

if 'vt-live-day' not in css:
    # 移动端：解除双向拆分隐藏（保留 mini 进度条隐藏）
    css = patch(css, r"\t\.vt-app \.vt-live-cell \.vt-mini, \.vt-app \.vt-live-split \{ display: none; \}",
        "\t.vt-app .vt-live-cell .vt-mini { display: none; }\n"
        "\t.vt-app .vt-live-split { display: block; }",
        'mobile live-split unhide')

    css += '''
/* statusflow: per-client day totals + client list pagination */
.vt-app .vt-live-day { font-size: var(--vt-fs-micro); color: var(--vt-text-3); white-space: nowrap; }
.vt-app .vt-live-day:not(:empty) { display: block; }
.vt-app .vt-pager { display: inline-flex; align-items: center; gap: 6px; margin-left: 8px; }
.vt-app .vt-pager .vt-btn { padding: 1px 8px; min-height: 0; line-height: 1.4; }
@media (pointer: coarse) {
        .vt-app .vt-pager { gap: 8px; }
        .vt-app .vt-pager .vt-btn { padding: 3px 12px; }
}
'''
    open(css_path, 'w', encoding='utf-8').write(css)
    print(f'vantage-statusflow: app.css patched ({len(css)} bytes)')
else:
    print('vantage-statusflow: app.css already patched, skip')
