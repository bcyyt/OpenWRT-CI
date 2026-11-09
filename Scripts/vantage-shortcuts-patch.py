#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# luci-app-vantage 仪表盘注入 statusfw 快捷方式条
# 用法：python3 vantage-shortcuts-patch.py <overview.js 路径>
# 兼容：源码版（未压缩）与 apk 产物（压缩）两种格式，锚点用正则宽松匹配。
# 注入内容：render() 顶层容器内、tile 网格之后追加独立区块（不参与 tile 拖拽布局）；
#           数据来自 /cgi-bin/statusmon 的 shortcuts 接口，60 秒刷新。
# 幂等：已注入时跳过。锚点缺失时报错退出（CI 可感知）。
import re
import sys

path = sys.argv[1]
src = open(path, encoding='utf-8').read()

if 'vt-scw-links' in src:
    print('vantage-shortcuts: already patched, skip')
    sys.exit(0)

GRID_RE = re.compile(
    r"this\.el\.grid\s*=\s*E\('div',\s*\{\s*'class':\s*'vt-grid vt-grid-wait'\s*\}\s*,\s*this\.buildTiles\(\)\)")
POLL_RE = re.compile(
    r"poll\.add\(L\.bind\(this\.refresh\s*,\s*this\)\s*,\s*POLL_S\)\s*;")

m = GRID_RE.search(src)
if not m:
    print('vantage-shortcuts: grid anchor not found', file=sys.stderr)
    sys.exit(1)
src = src[:m.end()] + (
    ",\n"
    "\t\t\tthis.el.shortcuts = E('section', { 'class': 'vt-scw', 'id': 'vt-scw' }, [\n"
    "\t\t\t\tE('div', { 'class': 'vt-scw-title' }, '快捷方式'),\n"
    "\t\t\t\tE('div', { 'class': 'vt-scw-links', 'id': 'vt-scw-links' }, [ E('span', { 'class': 'vt-scw-hint' }, '加载中…') ])\n"
    "\t\t\t])"
) + src[m.end():]

m2 = POLL_RE.search(src)
if not m2:
    print('vantage-shortcuts: poll anchor not found', file=sys.stderr)
    sys.exit(1)
src = src[:m2.end()] + "\n\t\tthis.initShortcuts();" + src[m2.end():]

METHOD = """
	,
	/* statusfw 快捷方式条（CI 注入）：仪表盘网格下方独立区块，不参与 tile 布局 */
	initShortcuts: function() {
		if (!document.getElementById('vt-scw-style')) {
			var st = document.createElement('style');
			st.id = 'vt-scw-style';
			st.textContent = ".vt-scw{margin-top:2px;border:1px solid rgba(127,127,127,.28);border-radius:12px;padding:12px 16px}.vt-scw-title{font-size:11px;letter-spacing:.8px;opacity:.55;margin:0 0 8px}.vt-scw-links{display:flex;flex-wrap:wrap;gap:8px}.vt-scw-links a{display:inline-flex;align-items:center;gap:6px;padding:6px 13px;border-radius:8px;border:1px solid rgba(127,127,127,.3);text-decoration:none;color:inherit;font-size:13px;font-weight:500;background:rgba(127,127,127,.06);transition:background .15s}.vt-scw-links a:hover{background:rgba(127,127,127,.14)}.vt-scw-links a svg{width:14px;height:14px;opacity:.75}.vt-scw-hint{font-size:12px;opacity:.5}";
			document.head.appendChild(st);
		}
		var wrap = document.getElementById('vt-scw-links');
		if (!wrap) return;
		var FIXED = [
			['网络设置', '/cgi-bin/luci/admin/network/network', 'M5 12.55a11 11 0 0114.08 0'],
			['系统管理', '/cgi-bin/luci/admin/system/admin', 'M12 15.5a5.5 5.5 0 10-11 0 5.5 5.5 0 0011 0zM19.4 15a1.65 1.65 0 00.33 1.82'],
			['文件管理', '/cgi-bin/luci/admin/system/filemanager', 'M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z']
		];
		var ICONS = {
			iptv: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2"/><polyline points="8 21 12 17 16 21"/></svg>',
			mediahub: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="2" width="20" height="20" rx="2"/><circle cx="12" cy="12" r="4"/></svg>',
			rtp2httpd: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>',
			lucky: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 010 20 15.3 15.3 0 010-20"/></svg>',
			daed: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>',
			natfrp: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/></svg>',
			docker: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="10" width="4" height="4"/><rect x="7" y="10" width="4" height="4"/><rect x="12" y="10" width="4" height="4"/><rect x="7" y="5" width="4" height="4"/><path d="M2 15h16a4 4 0 004-4"/></svg>',
			ttyd: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>',
			upnp: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82"/></svg>'
		};
		function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
		function svg(p) { return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="' + p + '"/></svg>'; }
		function scHref(h) { if (!h || h.charAt(0) === '/') return h; try { var u = new URL(h, location.href); u.hostname = location.hostname; return u.href; } catch (e) { return h; } }
		function render(list) {
			var html = '';
			FIXED.forEach(function(f) { html += '<a href="' + f[1] + '">' + svg(f[2]) + esc(f[0]) + '</a>'; });
			(list || []).forEach(function(s) {
				if (!s || !s.href || !s.label) return;
				html += '<a href="' + scHref(s.href) + '"' + ((s.target === '_blank' || s.id === 'rtp2httpd') ? ' target="_blank" rel="noopener noreferrer"' : '') + '>' + (ICONS[s.id] || svg('M10 13a5 5 0 007.54.54l3-3a5 5 0 00-7.07-7.07l-1.72 1.71M14 11a5 5 0 00-7.54-.54l-3 3a5 5 0 007.07 7.07l1.71-1.71')) + esc(s.label) + '</a>';
			});
			wrap.innerHTML = html;
		}
		function load() {
			fetch('/cgi-bin/statusmon', { cache: 'no-store' }).then(function(r) { return r.json(); }).then(function(d) { render(d.shortcuts || []); }).catch(function() {});
		}
		load();
		setInterval(load, 60000);
	}"""

tail = src.rstrip()
idx = tail.rfind('});')
if idx < 0:
    print('vantage-shortcuts: tail anchor not found', file=sys.stderr)
    sys.exit(1)
src = tail[:idx] + METHOD + '\n});\n'

open(path, 'w', encoding='utf-8').write(src)
print('vantage-shortcuts: injected into', path)
