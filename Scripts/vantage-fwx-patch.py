#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# luci-app-vantage 仪表盘注入 fwx 协议分析 + 今日流量排行 tile
# 用法：python3 vantage-fwx-patch.py <overview.js> <layout.js> <app.css>
# 目标格式：上游源码版（未压缩，tab 缩进）；
# 幂等：已注入时跳过。锚点缺失时非零退出（CI 可感知）。
import re
import sys

if len(sys.argv) != 4:
    print('用法: vantage-fwx-patch.py <overview.js> <layout.js> <app.css>', file=sys.stderr)
    sys.exit(2)

OV_PATH, LAYOUT_PATH, CSS_PATH = sys.argv[1], sys.argv[2], sys.argv[3]

ov = open(OV_PATH, encoding='utf-8').read()
layout = open(LAYOUT_PATH, encoding='utf-8').read()
css = open(CSS_PATH, encoding='utf-8').read()

if 'vt-fwx-donut' in ov:
    print('vantage-fwx: already patched, skip')
    sys.exit(0)


def must(expr, what, flags=0):
    m = re.search(expr, '', flags) # placeholder
    return None


def patch_regex(src, pattern, repl, what, count=1, flags=0):
    new, n = re.subn(pattern, repl, src, count=count, flags=flags)
    if n != count:
        print(f'vantage-fwx: anchor {what!r} matched {n} times (expect {count})', file=sys.stderr)
        sys.exit(1)
    return new


# ---------- overview.js ----------

# 1. rpc 声明 + 轮询间隔（插在 callBoard 声明后）
ov = patch_regex(ov,
    r"(var callBoard\s*=\s*rpc\.declare\(\{\s*object:\s*'system',\s*method:\s*'board'\s*\}\);)",
    r"""\1
var FWX_POLL_MS = 60000;
var callFwxCommon = rpc.declare({ object: 'fwx', method: 'common', params: [ 'api', 'data', 'CopyRight' ] });""",
    'callBoard declare')

# 2. buildTiles 增加 apps/rank
ov = patch_regex(ov,
    r"(this\.tiles\s*=\s*\{[^}]*?)(\};)",
    r"""\1,
                        apps: this.buildApps(), rank: this.buildRank()\2""",
    'buildTiles', flags=re.S)

# 3. tileNames 增加 apps/rank
ov = patch_regex(ov,
    r"(this\.tileNames\s*=\s*\{[^}]*?)(\};)",
    r"""\1,
                        apps: '协议分析', rank: '今日流量排行'\2""",
    'tileNames', flags=re.S)

# 4. paint 调用序列
ov = patch_regex(ov,
    r"(this\.paintTalkers\(\);)",
    r"\1 this.paintApps(); this.paintRank();",
    'paintTalkers call')

# 5. initFwx 调用（poll.add 主循环后）
ov = patch_regex(ov,
    r"(poll\.add\(\s*L\.bind\(this\.refresh,\s*this\),\s*POLL_S\)\s*;)",
    r"\1 this.initFwx();",
    'poll.add refresh')

# 6. 方法体（插在 buildTalkers 前，保持缩进）
FWX_METHODS = """fwxAvatarColor: function(name) {
                var palette = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4', '#f97316', '#ec4899', '#84cc16', '#6366f1'];
                var s = String(name || '?'), hash = 0;
                for (var i = 0; i < s.length; i++) hash = s.charCodeAt(i) + ((hash << 5) - hash);
                return palette[Math.abs(hash) % palette.length];
        },

        initFwx: function() {
                var self = this;
                this.fwx = { ok: false, err: 0, apps: null, rank: null, type: 'daily', busy: false };
                var un = function(r) { return (r && r.code === 2000 && r.data) ? r.data : null; };
                var er = function() { return 'ERR'; };
                this.fwxFetch = function() {
                        if (!self.fwx || self.fwx.busy) return;
                        self.fwx.busy = true;
                        Promise.all([
                                callFwxCommon('get_app_type_stats', { type: self.fwx.type, limit: 8 }, 'www.fanchmwrt.com').then(un).catch(er),
                                callFwxCommon('get_active_users', { count: 8 }, 'www.fanchmwrt.com').then(un).catch(er)
                        ]).then(function(rs) {
                                self.fwx.busy = false;
                                self.fwx.ok = (rs[0] !== 'ERR') || (rs[1] !== 'ERR');
                                if (!self.fwx.ok) self.fwx.err++;
                                if (rs[0] !== 'ERR') self.fwx.apps = rs[0];
                                if (rs[1] !== 'ERR') self.fwx.rank = rs[1];
                                self.paintApps();
                                self.paintRank();
                        });
                };
                this.fwxFetch();
                setInterval(this.fwxFetch, FWX_POLL_MS);
        },

        buildApps: function() {
                this.el.fwxDonut = E('div', { 'class': 'vt-fwx-donut' });
                this.el.fwxLegend = E('ul', { 'class': 'vt-fwx-legend' });
                return E('section', { 'class': 'vt-tile vt-apps', 'aria-label': '协议分析' }, [
                        tileHead('filter', '协议分析', [ E('span', { 'class': 'vt-hint' }, [ 'fwx' ]) ]),
                        E('div', { 'class': 'vt-fwx-body' }, [ this.el.fwxDonut, this.el.fwxLegend ])
                ]);
        },

        buildRank: function() {
                this.el.fwxRank = E('div', { 'class': 'vt-fwx-list' });
                return E('section', { 'class': 'vt-tile vt-rank', 'aria-label': '今日流量排行' }, [
                        tileHead('pulse', '今日流量排行', [ E('span', { 'class': 'vt-hint' }, [ 'fwx' ]) ]),
                        this.el.fwxRank
                ]);
        },

        paintApps: function() {
                var el = this.el.fwxDonut, lg = this.el.fwxLegend;
                if (!el) return;
                var fw = this.fwx || {};
                if (!fw.ok) {
                        dom.content(el, [ E('p', { 'class': 'vt-empty-inline' }, [ '需启用 fwx 应用统计服务' ]) ]);
                        if (lg) dom.content(lg, [ ]);
                        return;
                }
                var types = (fw.apps && Array.isArray(fw.apps.types)) ? fw.apps.types : [];
                if (!types.length) {
                        dom.content(el, [ E('p', { 'class': 'vt-empty-inline' }, [ '暂无应用统计数据' ]) ]);
                        if (lg) dom.content(lg, [ ]);
                        return;
                }
                var total = 0;
                types.forEach(function(t) { total += (t.total_time || 0); });
                if (total <= 0) total = 1;
                var segs = types.slice(0, 6);
                var rest = types.slice(6);
                if (rest.length) {
                        var rt = 0;
                        rest.forEach(function(t) { rt += (t.total_time || 0); });
                        segs.push({ name: '其他', total_time: rt });
                }
                var svg = svgRoot('vt-fwx-donut-svg', '0 0 36 36');
                var C = 2 * Math.PI * 15.5, acc = 0;
                segs.forEach(function(s, i) {
                        var frac = (s.total_time || 0) / total;
                        var seg = document.createElementNS(SVGNS, 'circle');
                        seg.setAttribute('cx', '18'); seg.setAttribute('cy', '18'); seg.setAttribute('r', '15.5');
                        seg.setAttribute('fill', 'none');
                        seg.setAttribute('class', 'vt-fwx-seg s' + (i % 5));
                        seg.setAttribute('stroke-dasharray', (frac * C).toFixed(2) + ' ' + C.toFixed(2));
                        seg.setAttribute('stroke-dashoffset', (-acc * C).toFixed(2));
                        acc += frac;
                        svg.appendChild(seg);
                });
                dom.content(el, [ svg, E('span', { 'class': 'vt-fwx-center' }, [ fmt.duration(total) ]) ]);
                if (lg) {
                        dom.content(lg, segs.map(function(s, i) {
                                return E('li', {}, [
                                        E('span', { 'class': 'vt-fwx-dot s' + (i % 5) }),
                                        E('span', { 'class': 'vt-fwx-lbl' }, [ String(s.name || ('类别 ' + (s.app_type || (i + 1)))) ]),
                                        E('span', { 'class': 'vt-fwx-val' }, [ fmt.duration(s.total_time || 0) ])
                                ]);
                        }));
                }
        },

        paintRank: function() {
                var el = this.el.fwxRank;
                if (!el) return;
                var fw = this.fwx || {}, avc = this.fwxAvatarColor;
                if (!fw.ok) {
                        dom.content(el, [ E('p', { 'class': 'vt-empty-inline' }, [ '需启用 fwx 应用统计服务' ]) ]);
                        return;
                }
                var users = (fw.rank && Array.isArray(fw.rank.users)) ? fw.rank.users.filter(function(u) { return u && typeof u === 'object'; }) : [];
                /* 字段兼容：fanchmwrt fwxd 返回 today_up_bytes/today_down_bytes，
                   旧版返回 up_bytes/down_bytes/total_bytes */
                var pick = function(u, keys) {
                        for (var i = 0; i < keys.length; i++) {
                                var v = u[keys[i]];
                                if (typeof v === 'number' && v >= 0) return v;
                        }
                        return 0;
                };
                var rowUp = function(u) { return pick(u, ['today_up_bytes', 'up_bytes', 'total_up_bytes']); };
                var rowDn = function(u) { return pick(u, ['today_down_bytes', 'down_bytes', 'total_down_bytes']); };
                var rows = users.map(function(u, i) {
                        var t = (typeof u.total_bytes === 'number' && u.total_bytes >= 0) ? u.total_bytes : (rowUp(u) + rowDn(u));
                        return { u: u, t: t, i: i };
                }).sort(function(a, b) { return b.t - a.t || a.i - b.i; }).slice(0, 8);
                if (!rows.length) {
                        dom.content(el, [ E('p', { 'class': 'vt-empty-inline' }, [ '暂无终端流量数据' ]) ]);
                        return;
                }
                var max = rows[0].t || 1;
                dom.content(el, rows.map(function(r, i) {
                        var u = r.u;
                        var name = String(u.nickname || '').trim() || String(u.hostname || '').trim() || String(u.mac || '').trim() || '--';
                        var tip = (name !== '--' ? '名称: ' + name + '\\n' : '') +
                                (u.mac ? 'MAC: ' + u.mac + '\\n' : '') + (u.ip ? 'IP: ' + u.ip + '\\n' : '') +
                                (u.is_wireless !== undefined ? '类型: ' + (u.is_wireless ? '无线' : '有线') + '\\n' : '') +
                                '上传: ' + fmt.bytes(rowUp(u)) + '\\n下载: ' + fmt.bytes(rowDn(u)) + '\\n合计: ' + fmt.bytes(r.t);
                        return E('div', { 'class': 'vt-fwx-row', 'title': tip }, [
                                E('span', { 'class': 'vt-fwx-rank' + (i < 3 ? ' top' : '') }, [ String(i + 1) ]),
                                E('span', { 'class': 'vt-fwx-avatar', 'style': 'background:' + avc(name) }, [
                                        name === '--' ? '?' : name.charAt(0).toUpperCase()
                                ]),
                                E('div', { 'class': 'vt-fwx-info' }, [
                                        E('div', { 'class': 'vt-fwx-name' }, [ name ]),
                                        E('div', { 'class': 'vt-fwx-meter' }, [
                                                E('div', { 'class': 'vt-fwx-track' }, [
                                                        E('span', { 'class': 'vt-fwx-fill', 'style': 'width:' + Math.max(2, Math.round(r.t / max * 100)) + '%' })
                                                ]),
                                                E('span', { 'class': 'vt-fwx-total' }, [ fmt.bytes(r.t) ])
                                        ])
                                ])
                        ]);
                }));
        },

"""

m = re.search(r'([ \t]*)buildTalkers:\s*function\s*\(', ov)
if not m:
    print('vantage-fwx: anchor buildTalkers method not found', file=sys.stderr)
    sys.exit(1)
indent = m.group(1)
block = FWX_METHODS.replace('\t', indent)
ov = ov[:m.start()] + block + ov[m.start():]

# ---------- layout.js ----------

layout = patch_regex(layout,
    r"(var TILES\s*=\s*\[)([^\]]*)(\])",
    r"\1\2, 'apps', 'rank'\3",
    'TILES list')

layout = patch_regex(layout,
    r"(\[\s*'ssids',\s*3,\s*1\s*\])\s*\],",
    r"\1, [ 'apps', 3, 1 ], [ 'rank', 0, 4 ] ],",
    'DEFAULTS wide')

# 手机(≤~600px)实际落在 mid 档：重排使 hero→chart→sys→协议→流量→无线，clients 沉底
layout = patch_regex(layout,
    r"mid:\s*\[\s*\[\s*'hero',\s*0,\s*2\s*\],\s*\[\s*'radios',\s*0,\s*2\s*\],\s*\[\s*'clients',\s*0,\s*2\s*\],\s*\[\s*'chart',\s*0,\s*2\s*\],\s*\[\s*'sys',\s*0,\s*1\s*\],\s*\[\s*'talk',\s*1,\s*1\s*\],\s*\[\s*'ssids',\s*1,\s*1\s*\]\s*\]",
    "mid: [ [ 'hero', 0, 2 ], [ 'chart', 0, 2 ], [ 'sys', 0, 1 ], [ 'apps', 1, 1 ], [ 'rank', 0, 2 ], [ 'radios', 0, 2 ], [ 'ssids', 0, 2 ], [ 'talk', 0, 2 ], [ 'clients', 0, 2 ] ]",
    'DEFAULTS mid')

# 手机端 narrow 整体重排：网络路径→吞吐量→系统→协议分析→流量排行→无线→终端列表沉底
# （用户要求：手机上 Clients 卡片显示在最下面）
layout = patch_regex(layout,
    r"narrow:\s*\[\s*\[\s*'clients',\s*0,\s*1\s*\],\s*\[\s*'talk',\s*0,\s*1\s*\],\s*\[\s*'radios',\s*0,\s*1\s*\],\s*\[\s*'hero',\s*0,\s*1\s*\],\s*\[\s*'ssids',\s*0,\s*1\s*\],\s*\[\s*'chart',\s*0,\s*1\s*\],\s*\[\s*'sys',\s*0,\s*1\s*\]\s*\]",
    "narrow: [ [ 'hero', 0, 1 ], [ 'chart', 0, 1 ], [ 'sys', 0, 1 ], [ 'apps', 0, 1 ], [ 'rank', 0, 1 ], [ 'radios', 0, 1 ], [ 'ssids', 0, 1 ], [ 'talk', 0, 1 ], [ 'clients', 0, 1 ] ]",
    'DEFAULTS narrow')

# 有线模式 wide：协议分析进右栏，流量排行满宽，clients 仍在 sys 下方列
layout = patch_regex(layout,
    r"(\[\s*'clients',\s*0,\s*4\s*\])\s*\],",
    r"\1, [ 'apps', 3, 1 ], [ 'rank', 0, 4 ] ],",
    'WIRED wide')

# 有线模式 mid/narrow：clients 沉底
layout = patch_regex(layout,
    r"mid:\s*\[\s*\[\s*'hero',\s*0,\s*2\s*\],\s*\[\s*'chart',\s*0,\s*2\s*\],\s*\[\s*'sys',\s*0,\s*2\s*\],\s*\[\s*'clients',\s*0,\s*2\s*\]\s*\]",
    "mid: [ [ 'hero', 0, 2 ], [ 'chart', 0, 2 ], [ 'sys', 0, 2 ], [ 'apps', 0, 2 ], [ 'rank', 0, 2 ], [ 'clients', 0, 2 ] ]",
    'WIRED mid')

layout = patch_regex(layout,
    r"narrow:\s*\[\s*\[\s*'hero',\s*0,\s*1\s*\],\s*\[\s*'clients',\s*0,\s*1\s*\],\s*\[\s*'chart',\s*0,\s*1\s*\],\s*\[\s*'sys',\s*0,\s*1\s*\]\s*\]",
    "narrow: [ [ 'hero', 0, 1 ], [ 'chart', 0, 1 ], [ 'sys', 0, 1 ], [ 'apps', 0, 1 ], [ 'rank', 0, 1 ], [ 'clients', 0, 1 ] ]",
    'WIRED narrow')

# ---------- app.css ----------

FWX_CSS = """

/* ---- fwx tiles: 协议分析 / 今日流量排行 ---- */
.vt-fwx-body { display: flex; align-items: center; gap: 12px; padding: 2px 0; min-height: 128px; }
.vt-fwx-donut { position: relative; width: 108px; height: 108px; flex: 0 0 auto; display: flex; align-items: center; justify-content: center; }
.vt-fwx-donut-svg { width: 108px; height: 108px; }
.vt-fwx-seg { stroke-width: 6; fill: none; }
.vt-fwx-seg.s0 { stroke: var(--vt-chart-1, #3b82f6); }
.vt-fwx-seg.s1 { stroke: var(--vt-chart-2, #10b981); }
.vt-fwx-seg.s2 { stroke: var(--vt-chart-3, #f59e0b); }
.vt-fwx-seg.s3 { stroke: var(--vt-chart-4, #8b5cf6); }
.vt-fwx-seg.s4 { stroke: var(--vt-chart-5, #ec4899); }
.vt-fwx-center { position: absolute; font: 500 var(--vt-fs-sm, 12px)/1.1 var(--vt-mono, monospace); }
.vt-fwx-legend { list-style: none; margin: 0; padding: 0; min-width: 0; flex: 1; display: flex; flex-direction: column; gap: 3px; }
.vt-fwx-legend li { display: flex; align-items: center; gap: 6px; font-size: var(--vt-fs-sm, 12px); }
.vt-fwx-dot { width: 8px; height: 8px; border-radius: 2px; flex: 0 0 auto; }
.vt-fwx-dot.s0 { background: var(--vt-chart-1, #3b82f6); }
.vt-fwx-dot.s1 { background: var(--vt-chart-2, #10b981); }
.vt-fwx-dot.s2 { background: var(--vt-chart-3, #f59e0b); }
.vt-fwx-dot.s3 { background: var(--vt-chart-4, #8b5cf6); }
.vt-fwx-dot.s4 { background: var(--vt-chart-5, #ec4899); }
.vt-fwx-lbl { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex: 1; }
.vt-fwx-val { font-variant-numeric: tabular-nums; opacity: .8; }
.vt-fwx-list { display: flex; flex-direction: column; gap: 7px; }
.vt-fwx-row { display: grid; grid-template-columns: 18px 30px minmax(0, 1fr); align-items: center; column-gap: 10px; padding: 3px 4px; border-radius: var(--vt-r-sm, 6px); transition: background .15s; }
.vt-fwx-row:hover { background: var(--vt-hover, rgba(127,127,127,.07)); }
.vt-fwx-rank { font: 600 var(--vt-fs-sm, 12px)/1 var(--vt-mono, monospace); color: var(--vt-chart-axis, #9ca3af); text-align: center; font-variant-numeric: tabular-nums; }
.vt-fwx-row:nth-child(1) .vt-fwx-rank { color: var(--vt-chart-1, #3b82f6); }
.vt-fwx-row:nth-child(2) .vt-fwx-rank { color: #06b6d4; }
.vt-fwx-row:nth-child(3) .vt-fwx-rank { color: var(--vt-chart-3, #f59e0b); }
.vt-fwx-avatar { width: 30px; height: 30px; border-radius: var(--vt-r, 8px); display: flex; align-items: center; justify-content: center; color: #fff; font: 600 13px/1 var(--vt-font, sans-serif); flex: 0 0 auto; }
.vt-fwx-info { min-width: 0; display: flex; flex-direction: column; gap: 3px; }
.vt-fwx-name { font: 500 var(--vt-fs-sm, 12px)/1.25 var(--vt-mono, ui-monospace); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.vt-fwx-meter { display: flex; align-items: center; gap: 8px; }
.vt-fwx-track { flex: 1; height: 5px; border-radius: 3px; background: var(--vt-meter, rgba(127,127,127,.16)); overflow: hidden; }
.vt-fwx-fill { display: block; height: 100%; border-radius: 3px; background: linear-gradient(90deg, var(--vt-chart-1, #3b82f6), #60a5fa); min-width: 2px; transition: width .4s; }
.vt-fwx-row:nth-child(1) .vt-fwx-fill { background: linear-gradient(90deg, var(--vt-dir-dn, #84cc16), #a3e635); }
.vt-fwx-total { font: 500 var(--vt-fs-micro, 11px)/1 var(--vt-mono, monospace); color: var(--vt-chart-axis, #6b7280); font-variant-numeric: tabular-nums; white-space: nowrap; min-width: 3.5em; text-align: right; }

/* 手机端：协议分析纵向堆叠、图例两列；流量排行缩字号自适应 */
@media (max-width: 768px) {
\t.vt-fwx-body { flex-direction: column; align-items: stretch; gap: 8px; }
\t.vt-fwx-donut { margin: 0 auto; }
\t.vt-fwx-legend { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 3px 10px; }
\t.vt-fwx-row { grid-template-columns: 14px 26px minmax(0, 1fr); column-gap: 8px; }
\t.vt-fwx-avatar { width: 26px; height: 26px; font-size: 12px; }
\t.vt-fwx-name { font-size: var(--vt-fs-micro, 11px); }
}
"""
css = css + FWX_CSS

open(OV_PATH, 'w', encoding='utf-8').write(ov)
open(LAYOUT_PATH, 'w', encoding='utf-8').write(layout)
open(CSS_PATH, 'w', encoding='utf-8').write(css)
print('vantage-fwx: patched 3 files OK')
