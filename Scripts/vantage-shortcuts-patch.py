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

HEALTH_RE = re.compile(r"this\.el\.health\s*=")
POLL_RE = re.compile(
    r"poll\.add\(L\.bind\(this\.refresh\s*,\s*this\)\s*,\s*POLL_S\)\s*;")

m = HEALTH_RE.search(src)
if not m:
    print('vantage-shortcuts: health anchor not found', file=sys.stderr)
    sys.exit(1)
src = src[:m.start()] + (
    "this.el.shortcuts = E('section', { 'class': 'vt-scw', 'id': 'vt-scw' }, [\n"
    "\t\t\t\tE('div', { 'class': 'vt-scw-title' }, '快捷方式'),\n"
    "\t\t\t\tE('div', { 'class': 'vt-scw-links', 'id': 'vt-scw-links' }, [ E('span', { 'class': 'vt-scw-hint' }, '加载中…') ])\n"
    "\t\t\t]),\n"
    "\t\t\t"
) + src[m.start():]

m2 = POLL_RE.search(src)
if not m2:
    print('vantage-shortcuts: poll anchor not found', file=sys.stderr)
    sys.exit(1)
src = src[:m2.end()] + "\n\t\tthis.initShortcuts();\n\t\tthis.initPpe();" + src[m2.end():]

# --- CPU 卡片 PPE 显示（v3）：兼容 main 源码版与 apk 压缩版两种 buildSystem ---
PPE_DEF_RE = re.compile(
    r"(el\.cpuTemp\s*=\s*E\('span'\s*,\s*\{\s*'class'\s*:\s*'vt-hint vt-tn'\s*\}\s*\)(\s*[;,]?))"
    r"|(el\.cpuLoad\s*=\s*E\('span',\s*\{\s*'class':\s*'vt-hint vt-tn',\s*'title':\s*_\('Load average over 1, 5 and 15 minutes'\)\s*\}\s*\)\s*;)")
m3 = PPE_DEF_RE.search(src)
if not m3:
    print('vantage-shortcuts: ppe def anchor not found', file=sys.stderr)
    sys.exit(1)
if m3.group(1):
    src = src[:m3.end(1)] + "el.ppeInfo=E('span',{'class':'vt-hint vt-tn','id':'vt-ppe','hidden':''})" + m3.group(2) + src[m3.end(1):]
else:
    src = src[:m3.end(3)] + "\n\t\tel.ppeInfo = E('span', { 'class': 'vt-hint vt-tn', 'id': 'vt-ppe', 'hidden': '' });" + src[m3.end(3):]

PPE_REF_COMPACT = re.compile(r"el\.cpuLoad\s*,\s*el\.cpuTemp\s*\]\)")
PPE_REF_MAIN = re.compile(r"(el\.cpuVal,\s*el\.cpuLoad)(\s*\n\s*\])")
if PPE_REF_COMPACT.search(src):
    src = PPE_REF_COMPACT.sub("el.cpuLoad,el.cpuTemp,el.ppeInfo])", src, count=1)
elif PPE_REF_MAIN.search(src):
    src = PPE_REF_MAIN.sub(r"\1, el.ppeInfo\2", src, count=1)
else:
    print('vantage-shortcuts: ppe ref anchor not found', file=sys.stderr)
    sys.exit(1)

METHOD = """
        ,
        /* statusfw 快捷方式条（CI 注入）：仪表盘页头下方顶部，独立区块不参与 tile 布局 */
        initShortcuts: function() {
                if (!document.getElementById('vt-scw-style')) {
                        var st = document.createElement('style');
                        st.id = 'vt-scw-style';
                        st.textContent = ".vt-scw{margin:0 0 10px;border:1px solid rgba(127,127,127,.28);border-radius:12px;padding:12px 16px}.vt-scw-title{font-size:11px;letter-spacing:.8px;opacity:.55;margin:0 0 8px}.vt-scw-links{display:flex;flex-wrap:wrap;gap:8px}.vt-scw-links a{display:inline-flex;align-items:center;gap:6px;padding:6px 13px;border-radius:8px;border:1px solid rgba(127,127,127,.3);text-decoration:none;color:inherit;font-size:13px;font-weight:500;background:rgba(127,127,127,.06);transition:background .15s}.vt-scw-links a:hover{background:rgba(127,127,127,.14)}.vt-scw-links a svg{width:14px;height:14px;opacity:.75}.vt-scw-hint{font-size:12px;opacity:.5}.vt-chip-main .vt-chip-reason.vt-ppe-chip{white-space:normal;word-break:break-word;opacity:.92}";
                        document.head.appendChild(st);
                }
                /* render 阶段节点尚未挂载进文档，必须用节点引用而非 getElementById */
                var wrap = (this.el && this.el.shortcuts) ? this.el.shortcuts.querySelector('.vt-scw-links') : null;
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
        }
        ,
        /* PPE 硬件 offload 占用（CI 注入）：System 卡片标签行 + 健康条 CPU 卡片，分引擎 IPv4/IPv6 细分 */
        initPpe: function() {
                var self = this;
                function fmtPpe(d) {
                        function part(name, p) {
                                if (!p || !p.t) return name + ': 0 (IPv4: 0 IPv6: 0)';
                                return name + ': ' + p.t + ' (IPv4: ' + (p.v4 || 0) + ' IPv6: ' + (p.v6 || 0) + ')';
                        }
                        return 'USR: ' + (d.usr || 0) + '% SYS: ' + (d.sys || 0) + '% ' + part('PPE0', d.ppe0) + ' ' + part('PPE1', d.ppe1);
                }
                function paintTile(el, text) {
                        if (!el) return;
                        if (!text) { el.hidden = true; return; }
                        el.hidden = false;
                        if (el.textContent !== text) el.textContent = text;
                }
                function cpuChips() {
                        var found = [];
                        document.querySelectorAll('.vt-chip').forEach(function(chip) {
                                var t = chip.querySelector('.vt-chip-title'), main = chip.querySelector('.vt-chip-main');
                                if (t && main && t.textContent === 'CPU') found.push(main);
                        });
                        return found;
                }
                function load() {
                        fetch('/cgi-bin/statusppe', { cache: 'no-store' }).then(function(r) { return r.json(); }).then(function(d) {
                                var text = (d && d.hw) ? fmtPpe(d) : null;
                                paintTile(self.el && self.el.ppeInfo, text);
                                cpuChips().forEach(function(main) {
                                        if (!main.ppeChip) {
                                                main.ppeChip = document.createElement('span');
                                                main.ppeChip.className = 'vt-chip-reason vt-ppe-chip';
                                                main.appendChild(main.ppeChip);
                                        }
                                        main.ppeChip.hidden = !text;
                                        if (text && main.ppeChip.textContent !== text) main.ppeChip.textContent = text;
                                        if (!text && main.ppeChip.textContent) main.ppeChip.textContent = '';
                                });
                        }).catch(function() { paintTile(self.el && self.el.ppeInfo, null); });
                }
                load();
                setInterval(load, 30000);
                /* 健康条芯片重建后自动补 PPE 行 */
                var target = (self.el && self.el.health) || document.querySelector('.vt-health');
                if (target && window.MutationObserver) {
                        var mo = new MutationObserver(function() { load(); });
                        mo.observe(target, { childList: true, subtree: true });
                }
        }"""

tail = src.rstrip()
idx = tail.rfind('});')
if idx < 0:
    print('vantage-shortcuts: tail anchor not found', file=sys.stderr)
    sys.exit(1)
src = tail[:idx] + METHOD + '\n});\n'

open(path, 'w', encoding='utf-8').write(src)
print('vantage-shortcuts: injected into', path)
