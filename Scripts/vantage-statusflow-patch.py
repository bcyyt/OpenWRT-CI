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
# v5（24h 曲线）：
#   7) WAN/CPU 抽屉 5min/1h/24h 档位大图（数据源 /cgi-bin/seriesmon，worker 30s 采样）
#   8) 悬停/触摸十字线 + 时间数值气泡读数（触摸 1.6s 自动隐藏，pan-y 不挡滚动）
#   9) CPU 火花线与 uplink/cpu 健康芯片点击直达历史抽屉；#perf hash 直达
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



# ---------- statusflow v5: 24h zoom charts (CPU / WAN) ----------
# 数据源 /cgi-bin/seriesmon（worker 30s 采样 tmpfs series.jsonl）。
# WAN/CPU 抽屉 5min/1h/24h 档位曲线 + 悬停/触摸十字线读数。

ZOOM_HELPERS = "/* ── v-zoom: 仪表盘 24h 曲线放大层（CPU / WAN，数据源 /cgi-bin/seriesmon）── */\nvar srCache=null, srAt=0, srBusy=null;\nfunction fetchSeries(force){\n        var now=Date.now();\n        if(!force&&srCache&&now-srAt<60000)return Promise.resolve(srCache);\n        if(srBusy)return srBusy;\n        srBusy=fetch('/cgi-bin/seriesmon',{cache:'no-store'}).then(function(r){return r.text();}).then(function(t){\n                var pts=[];\n                t.split('\\n').forEach(function(l){\n                        l=l.trim();if(!l)return;\n                        try{var v=JSON.parse(l);if(v&&isFinite(v.t))pts.push([v.t*1000,+v.c||0,+v.d||0,+v.u||0]);}catch(e){}\n                });\n                return pts;\n        });\n        var ok=function(p){srCache=p;srAt=Date.now();},bad=function(){srCache=[];srAt=Date.now();},done=function(){srBusy=null;};\n        srBusy.then(ok,bad);srBusy.then(done,done);\n        return srBusy;\n}\nfunction zoomT(t){var d=new Date(t),p=function(n){return(n<10?'0':'')+n;};return p(d.getHours())+':'+p(d.getMinutes());}\nfunction zoomTL(t,rg){var d=new Date(t),p=function(n){return(n<10?'0':'')+n;};var hm=p(d.getHours())+':'+p(d.getMinutes());return rg==='24h'?(d.getMonth()+1)+'-'+p(d.getDate())+' '+hm:hm;}\nfunction zoomY(kind,v){return kind==='cpu'?Math.round(v)+'%':bitsLabel(v);}\nfunction zoomHost(view,kind){\n        var key=kind==='cpu'?'zoomCpu':'zoomWan', rg=(view.ui&&view.ui[key])||'5m';\n        var winMs=rg==='1h'?3600000:rg==='24h'?86400000:300000, now=Date.now();\n        var data=[];\n        if(rg==='5m'){\n                var src;\n                if(kind==='cpu')src=(view.st.hist.cpu||[]).slice();\n                else{var up=view.m&&view.m.uplink;src=up?(view.st.hist.net[lineKey(up)]||[]):[];}\n                data=src.filter(function(p){return p[0]>=now-winMs;});\n        }else if(srCache){\n                data=srCache.filter(function(p){return p[0]>=now-winMs;}).map(function(p){\n                        return kind==='cpu'?[p[0],p[1]]:[p[0],p[2],p[3]];\n                });\n        }\n        var body=(data.length>1)?zoomChart(kind,data,rg)\n                :E('p',{'class':'vt-empty-inline'},[srCache?_('No data in this window yet.'):_('Loading history…')]);\n        if(rg!=='5m'&&(!srCache||now-srAt>60000))\n                fetchSeries().then(function(){if(view.ui.drawer&&view.el.drawer&&!view.el.drawer.hidden)view.paintDrawer();},function(){});\n        return E('div',{'class':'vt-zoom'},[zoomBar(view,key,kind),body]);\n}\nfunction zoomBar(view,key,kind){\n        var rg=(view.ui&&view.ui[key])||'5m';\n        function btn(id,lab){return E('button',{'type':'button','class':'vt-btn vt-zoom-btn'+(rg===id?' vt-zoom-on':''),'click':function(){view.ui[key]=id;view.paintDrawer();}},[lab]);}\n        var legend=kind==='wan'\n                ?E('span',{'class':'vt-zoom-lg'},[E('i',{'class':'vt-zg vt-zg-dn'}),_('Down','vantage'),E('i',{'class':'vt-zg vt-zg-up'}),_('Up','vantage')])\n                :E('span',{'class':'vt-zoom-lg'},[E('i',{'class':'vt-zg vt-zg-cpu'}),_('CPU','vantage')]);\n        return E('div',{'class':'vt-zoom-bar'},[btn('5m',_('5 min')),btn('1h',_('1 hour')),btn('24h',_('24 hours')),legend]);\n}\nfunction zoomChart(kind,data,rg){\n        var winMs=rg==='1h'?3600000:rg==='24h'?86400000:300000;\n        var t1=data[data.length-1][0], t0=Math.max(data[0][0], t1-winMs);\n        var gapMs=rg==='5m'?9000:100000;\n        var cols=kind==='cpu'?[[1,'var(--vt-chart-5)']]:[[1,'var(--vt-dir-dn)'],[2,'var(--vt-series-up)']];\n        var peak=[],sum=[],cnt=0,i;\n        for(i=0;i<cols.length;i++){peak[i]=0;sum[i]=0;}\n        data.forEach(function(p){\n                if(p[0]<t0||p[0]>t1)return;cnt++;\n                for(i=0;i<cols.length;i++){var v=p[cols[i][0]];if(isFinite(v)&&v>peak[i])peak[i]=v;sum[i]+=isFinite(v)?v:0;}\n        });\n        var vmax=kind==='cpu'?100:series.niceCeil(Math.max(Math.max.apply(null,peak)*1.08,1000));\n        var wrap=E('div',{'class':'vt-zoom-chart'});\n        var plot=E('div',{'class':'vt-zoom-plot'});\n        var svg=svgRoot('vt-spark','0 0 100 100');\n        svg.setAttribute('preserveAspectRatio','none');\n        for(i=1;i<4;i++)svg.appendChild(svgPath('M0 '+(100-25*i)+'H100','vt-spark-grid'));\n        svg.appendChild(svgPath('M0 100H100','vt-spark-base'));\n        cols.forEach(function(c){\n                var segs=series.segments(data,c[0],t0,t1,vmax,100,100,gapMs);\n                if(!segs.length)return;\n                if(c[0]===1){var area=svgPath(series.areaPath(segs,100),'vt-zoom-area');area.style.fill=c[1];svg.appendChild(area);}\n                var line=svgPath(series.linePath(segs),'vt-spark-line');\n                line.style.stroke=c[1];svg.appendChild(line);\n        });\n        plot.appendChild(svg);\n        for(i=0;i<4;i++){var yl=E('span',{'class':'vt-zoom-yl'},[zoomY(kind,vmax*(4-i)/4)]);yl.style.top=(i*25)+'%';plot.appendChild(yl);}\n        /* ── 悬停/触摸读数：十字线 + 数值气泡 ── */\n        var cross=E('div',{'class':'vt-zoom-cross'});\n        var tip=E('div',{'class':'vt-zoom-tip'});\n        var dots=cols.map(function(c){var d=E('div',{'class':'vt-zoom-dot'});d.style.background=c[1];plot.appendChild(d);return d;});\n        plot.appendChild(cross);plot.appendChild(tip);\n        var hideT=0;\n        function hideNow(){cross.style.display='none';tip.style.display='none';dots.forEach(function(d){d.style.display='none';});}\n        function show(p,px){\n                cross.style.display='block';cross.style.left=px+'%';\n                tip.style.display='block';tip.textContent='';\n                tip.appendChild(E('b',{},[zoomTL(p[0],rg)]));\n                cols.forEach(function(c,ci){\n                        var v=p[c[0]];if(!isFinite(v))return;\n                        dots[ci].style.display='block';\n                        dots[ci].style.left=px+'%';\n                        dots[ci].style.top=((1-Math.max(0,Math.min(1,v/vmax)))*100)+'%';\n                        tip.appendChild(E('span',{'class':'vt-zoom-tip-i'},[E('i',{'class':'vt-zg vt-zg'+(kind==='cpu'?'-cpu':ci?'-up':'-dn')}),zoomY(kind,v)]));\n                });\n                var r=plot.getBoundingClientRect(),lx=px/100*r.width,tw=tip.offsetWidth||80;\n                tip.style.left=Math.max(tw/2+4,Math.min(r.width-tw/2-4,lx))+'px';\n        }\n        function move(ev){\n                var r=plot.getBoundingClientRect();\n                var fx=(ev.clientX-r.left)/r.width;\n                if(!(fx>=0)||fx>1){hideNow();return;}\n                var tt=t0+fx*(t1-t0),best=null,bd=Infinity;\n                for(var j=0;j<data.length;j++){var d=Math.abs(data[j][0]-tt);if(d<bd){bd=d;best=data[j];}}\n                if(!best){hideNow();return;}\n                show(best,(best[0]-t0)/(t1-t0)*100);\n                if(hideT){clearTimeout(hideT);hideT=0;}\n        }\n        function hideLater(){if(hideT)clearTimeout(hideT);hideT=setTimeout(hideNow,1600);}\n        plot.addEventListener('pointermove',move);\n        plot.addEventListener('pointerdown',move);\n        plot.addEventListener('pointerleave',function(){if(hideT){clearTimeout(hideT);hideT=0;}hideNow();});\n        plot.addEventListener('pointercancel',function(){hideNow();});\n        plot.addEventListener('pointerup',function(ev){if(ev.pointerType!=='mouse')hideLater();});\n        hideNow();\n        wrap.appendChild(plot);\n        var xl=E('div',{'class':'vt-zoom-xl'});\n        for(i=0;i<5;i++)xl.appendChild(E('span',{},[zoomT(t0+(t1-t0)*i/4)]));\n        wrap.appendChild(xl);\n        var last=data[data.length-1];\n        var st=kind==='cpu'\n                ?_('Peak %s · avg %s').format(Math.round(peak[0])+'%',cnt?Math.round(sum[0]/cnt)+'%':fmt.DASH)\n                :_('Peak ↓ %s · ↑ %s').format(bitsLabel(peak[0]),bitsLabel(peak[1]));\n        var cur=kind==='cpu'?Math.round(last[1])+'%':_('now ↓ %s · ↑ %s').format(bitsLabel(last[1]),bitsLabel(last[2]));\n        wrap.appendChild(E('div',{'class':'vt-zoom-stat'},[st+' — '+cur]));\n        return wrap;\n}\nfunction drawerPerfBody(view){\n        var m=view.m||{},dev=m.device||{},load=dev.load||[],cores=view.st&&view.st.cores;\n        return{title:[E('span',{'class':'vt-drawer-ico'},[icon('cpu')]),\n                E('div',{'class':'vt-drawer-titles'},[\n                        E('div',{'class':'vt-drawer-name'},[_('CPU performance')]),\n                        E('div',{'class':'vt-drawer-sub'},[(cores?cores+' cores · ':'')+(load.length?('load '+(load[0]/65536).toFixed(2)+' / '+(load[1]/65536).toFixed(2)+' / '+(load[2]/65536).toFixed(2)):'')])])],\n                body:[zoomHost(view,'cpu'),\n                        view.section(_('Snapshot','vantage'),[E('dl',{'class':'vt-kvs'},[\n                                kv(_('CPU','vantage'),dev.system||fmt.DASH),\n                                kv(_('Target','vantage'),dev.target||fmt.DASH),\n                                kv(_('Kernel','vantage'),dev.kernel||fmt.DASH),\n                                kv(_('Load average'),load.length?load.map(function(v){return(v/65536).toFixed(2);}).join(' / '):fmt.DASH)])])]};\n}\n"

def zrep(find, to, what):
    global ov
    n = ov.count(find)
    if n != 1:
        print(f'statusflow-zoom: anchor {what!r} matched {n} times (expect 1)', file=sys.stderr)
        sys.exit(1)
    ov = ov.replace(find, to, 1)

if 'zoomHost' not in ov:
    # z1) helpers（fetch/档位/图表/tooltip 工具函数）+ view.drawerPerf 方法
    zrep('return view.extend({\n\thandleSave: null,\n\thandleSaveApply: null,\n\thandleReset: null,\n',
        ZOOM_HELPERS + '\nreturn view.extend({\n\thandleSave: null,\n\thandleSaveApply: null,\n\thandleReset: null,\n\n\tdrawerPerf: function() { return drawerPerfBody(this); },\n',
        'helpers+drawerPerf')

    # z2) uplink 抽屉 5 分钟 sparkline → 档位切换曲线
    zrep("E('div', { 'class': 'vt-dspark' }, [ sparkline(hist || [], [ 1, 2 ], 0, 'vt-spark-up', { min: 1000, scale: bitsLabel }) ])",
        "zoomHost(this, 'wan')",
        'drawerUplink zoom')

    # z3) paintDrawer 增加 perf 分支
    zrep('else content = this.drawerDevice();',
        "else if (d.kind === 'perf') content = this.drawerPerf(); else content = this.drawerDevice();",
        'paintDrawer perf')

    # z4) hash 路由 #perf
    zrep("if (hash === '#uplink') { this.openDrawer('uplink', ''); return; }",
        "if (hash === '#uplink') { this.openDrawer('uplink', ''); return; }\n\t\tif (hash === '#perf') { this.openDrawer('perf', ''); return; }",
        'hash perf')

    # z5) uplink/cpu 健康芯片点击直达抽屉
    zrep("else if (c.client) this.openDrawer('client', c.client);",
        "else if (c.client) this.openDrawer('client', c.client); else if (c.id === 'uplink') this.openDrawer('uplink', ''); else if (c.id === 'cpu') this.openDrawer('perf', '');",
        'openCheck route')

    # z6) sys 卡构建器暴露 self
    zrep("buildSystem: function() {\n\t\tvar el = this.el;\n\t\tel.sysUptime = E('span', { 'class': 'vt-hint vt-tn' });",
        "buildSystem: function() {\n\t\tvar el = this.el, self = this;\n\t\tel.sysUptime = E('span', { 'class': 'vt-hint vt-tn' });",
        'sys self')

    # z7) CPU 火花线可点击 → perf 抽屉
    zrep("el.cpuSpark = E('div', { 'class': 'vt-spark-slot' });",
        "el.cpuSpark = E('div', { 'class': 'vt-spark-slot vt-zoomable', 'title': _('Click to open history'), 'click': function() { self.openDrawer('perf', ''); } });",
        'cpuSpark clickable')

    print('vantage-statusflow: zoom charts patched')

# ---------- zte mesh 无线详情徽标 (statusflow v5.3) ----------
# 数据链路：/usr/lib/zte-wifi.py（procd 守护，ZXSLC 协议登中兴各节点拉本节点 WiFi
# 客户端 + 主节点拓扑）→ /tmp/zte-wifi.json → /www/cgi-bin/zteinfo → 前端每 15s 轮询。
# 客户端行显示「5G · 节点名」/「2.4G · 节点名」accent 徽标，mesh 节点行显示「ZTE mesh 主/子」。
# 未配置 /etc/zte-wifi.conf 时守护不启动，此段静默无数据，不影响页面。

# Z1) 挂载：initFlow 后追加 initZte
ov = patch(ov, r"(\t\tthis\.initFlow\(\);)",
    r"\1\n\t\tthis.initZte();",
    'initZte hook')

# Z2) initZte 方法（插在 initFlow 定义前）
zte_method = '''
        /* zte: 中兴 mesh 无线详情徽标（/cgi-bin/zteinfo，zte-wifi 守护采集中兴路由器 API）*/
        initZte: function() {
                var self = this;
                function load() {
                        fetch('/cgi-bin/zteinfo', { cache: 'no-store' })
                                .then(function(r) { return r.json(); })
                                .catch(function() { return null; })
                                .then(function(d) {
                                        if (!d) return;
                                        var c = d.c || {}, n = d.n || {}, chg = false, k;
                                        if (!self.st.zte) {
                                                self.st.zte = c; self.st.zteNode = n;
                                                chg = Object.keys(c).length > 0;
                                        } else {
                                                for (k in c) if (JSON.stringify(self.st.zte[k]) !== JSON.stringify(c[k])) { chg = true; break; }
                                                if (!chg) for (k in n) if (!self.st.zteNode || JSON.stringify(self.st.zteNode[k]) !== JSON.stringify(n[k])) { chg = true; break; }
                                                self.st.zte = c; self.st.zteNode = n;
                                        }
                                        if (chg) self.paintClients();
                                });
                }
                load();
                setInterval(load, 15000);
        },

'''
ov = patch(ov, r"(initFlow: function\(\) \{)",
    zte_method + r"\1",
    'initZte method')

# Z3) wiredCells 徽标（VLAN pill 之后；锚点宽容空白，兼容源码格式差异）
ov = patch(ov,
    r"(if\s*\(\s*c\.vlan\s*!=\s*null\s*\)\s*tags\.push\s*\(\s*pill\s*\(\s*_\s*\(\s*'VLAN %d'\s*\)\s*\.format\s*\(\s*c\.vlan\s*\)\s*,\s*'muted'\s*\)\s*\)\s*;)",
    r"\1"
    r"var zw=null,zn=null,zt=this.st.zte||{},ztN=this.st.zteNode||{},zips=c&&c.ips||[];"
    r"for(var zi=0;zi<zips.length;zi++){if(zt[zips[zi]]){zw=zt[zips[zi]];break;}"
    r"if(!zn&&ztN[zips[zi]])zn=ztN[zips[zi]];}"
    r"if(zw){var zl=(zw.m?zw.m+' · ':'')+zw.b+' · '+zw.n;"
    r"var zt='中兴 mesh 无线：'+zw.b+'，节点「'+zw.n+'」';"
    r"if(zw.mac)zt+='\nMAC: '+zw.mac;"
    r"function zfr(v){if(v==null)return'-';if(v>=1e9)return(v/1e9).toFixed(1)+'Gbps';if(v>=1e6)return(v/1e6).toFixed(1)+'Mbps';if(v>=1e3)return(v/1e3).toFixed(0)+'Kbps';return v+'bps';}"
    r"if(zw.ur!=null)zt+='\n实时速率: ↑'+zfr(zw.ur)+' ↓'+zfr(zw.dr);"
    r"if(zw.ut!=null)zt+='\n累计吞吐(KB): ↑'+zw.ut+' ↓'+zw.dt;"
    r"if(zw.on!=null){var zd=Math.floor(zw.on/86400),zh=Math.floor(zw.on%86400/3600),zm=Math.floor(zw.on%3600/60);zt+='\n在线: '+(zd?zd+'天 ':'')+zh+'时'+zm+'分';}"
    r"if(zw.lc)zt+='\n最后连接: '+zw.lc;"
    r"tags.push(pill(zl,'accent',zt));}"
    r"else if(zn){var nt='中兴 mesh 节点：'+zn.m;"
    r"if(zn.md)nt+='\n型号: '+zn.md;"
    r"if(zn.sv)nt+='\n固件: '+zn.sv;"
    r"if(zn.at)nt+='\n回程: '+zn.at+(zn.ls&&zn.ls!='0'?' '+zn.ls+'Mbps':'');"
    r"tags.push(pill('ZTE mesh '+zn.r,'accent',nt));}",
    'wiredCells zte badge')

# CSS（追加在原 statusflow CSS 之后）

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

zoom_css = '/* v-zoom: 24h history charts (CPU / WAN) — appended by statusflow v5 */\n.vt-app .vt-zoom { margin: 2px 0 4px; }\n.vt-app .vt-zoom-bar { display: flex; align-items: center; gap: 6px; margin: 0 0 10px; flex-wrap: wrap; }\n.vt-app .vt-zoom-btn { padding: 1px 12px; min-height: 24px; line-height: 1.4; border-radius: 999px; }\n.vt-app .vt-zoom-on { background: color-mix(in oklab, var(--vt-chart-1) 22%, transparent); }\n.vt-app .vt-zoom-lg { margin-left: auto; display: inline-flex; align-items: center; gap: 6px; font-size: var(--vt-fs-micro); color: var(--vt-text-3); }\n.vt-app .vt-zg { width: 10px; height: 3px; border-radius: 2px; display: inline-block; }\n.vt-app .vt-zg-dn { background: var(--vt-dir-dn); }\n.vt-app .vt-zg-up { background: var(--vt-series-up); }\n.vt-app .vt-zg-cpu { background: var(--vt-chart-5); }\n.vt-app .vt-zoom-plot { position: relative; }\n.vt-app .vt-zoom-plot .vt-spark { height: 230px; }\n.vt-app .vt-zoom-area { opacity: .14; }\n.vt-app .vt-zoom-yl { position: absolute; right: 0; font-size: var(--vt-fs-micro); color: var(--vt-chart-axis); transform: translateY(-50%); pointer-events: none; }\n.vt-app .vt-zoom-xl { display: flex; justify-content: space-between; margin-top: 4px; font-size: var(--vt-fs-micro); color: var(--vt-text-3); }\n.vt-app .vt-zoom-stat { margin: 8px 2px 2px; font-size: var(--vt-fs-micro); color: var(--vt-text-3); }\n.vt-app .vt-zoomable { cursor: zoom-in; }\n@media (max-width: 640px) {\n\t.vt-app .vt-zoom-plot .vt-spark { height: 38vh; min-height: 180px; }\n\t.vt-app .vt-zoom-btn { padding: 3px 14px; }\n}\n\n/* v-zoom tooltip: hover/touch readout (statusflow v5.1) */\n.vt-app .vt-zoom-plot { touch-action: pan-y; user-select: none; -webkit-user-select: none; cursor: crosshair; }\n.vt-app .vt-zoom-cross { position: absolute; top: 0; bottom: 0; width: 1px; background: var(--vt-chart-axis); opacity: .55; pointer-events: none; display: none; }\n.vt-app .vt-zoom-dot { position: absolute; width: 9px; height: 9px; margin: -4.5px 0 0 -4.5px; border-radius: 50%; box-shadow: 0 0 0 2px var(--vt-surface); pointer-events: none; display: none; }\n.vt-app .vt-zoom-tip { position: absolute; top: 4px; transform: translateX(-50%); background: var(--vt-surface); border: 1px solid var(--vt-chart-grid); border-radius: 8px; padding: 3px 10px; font-size: var(--vt-fs-micro); color: var(--vt-text-2); white-space: nowrap; pointer-events: none; display: none; box-shadow: 0 2px 10px rgba(0,0,0,.18); z-index: 5; }\n.vt-app .vt-zoom-tip b { font-weight: 600; margin-right: 6px; color: var(--vt-text-1); }\n.vt-app .vt-zoom-tip-i { margin-right: 8px; display: inline-flex; align-items: center; gap: 4px; }\n.vt-app .vt-zoom-tip-i:last-child { margin-right: 0; }\n/* v-zoom fix: pin plot height, svg fills it (statusflow v5.2) */\n.vt-app .vt-zoom-plot { height: 180px; }\n.vt-app .vt-zoom-plot svg.vt-spark { width: 100%; height: 100%; display: block; }\n@media (max-width: 640px) {\n\t.vt-app .vt-zoom-plot { height: 38vh; min-height: 180px; }\n}'
if 'vt-zoom-chart' not in css:
    css += zoom_css
    open(css_path, 'w', encoding='utf-8').write(css)
    print(f'vantage-statusflow: zoom css appended ({len(css)} bytes)')
else:
    print('vantage-statusflow: zoom css already present, skip')
