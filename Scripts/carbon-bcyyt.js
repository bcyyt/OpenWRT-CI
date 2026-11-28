/* carbon-bcyyt v3.2 — PPE 环+明细 / IPv6 完整显示 / CPU 环点击历史曲线
 * v3.2: PPE 明细行口径修正——表项改"占用/容量"(152/4096)对齐环副标;
 *       v4/v6 正名为条目分布, 新增真绑定明细 bv4/bv6(用户实机反馈)
 * v3.1: 非概览页静默自毁(修跨页污染弹标 bug, 2026-11-28 实机)
 * v3.0: ① CPU 环可点击 → 弹出 3h/24h 历史曲线(数据 /cgi-bin/adash?sys_hist=1)
 *       ② IPv6 手机/电脑显示不全修复(.cb-ip6 放开换行 word-break)
 * v2.2: MutationObserver 抗 Carbon 15s 重渲染
 * 数据源: /cgi-bin/adash (25s 缓存) + ?sys_hist=1 (每分钟点列, 60s 前端缓存)
 * 卸载: 删本文件 + footer.ut 中标 <!-- bcyyt badges --> 的行
 */
(function () {
	'use strict';
	if (window.__carbonBcyytLoaded) return;
	window.__carbonBcyytLoaded = true;

	var dbg = 0;
	var timer = null;
	var fmtOk = null;

	function esc(s) {
		return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
			return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
		});
	}

	/* ═══════════ ① 样式注入: IPv6 修复 + CPU 环手势 + 弹层 ═══════════ */
	function injectStyle() {
		if (document.getElementById('cb-bcyyt-style')) return;
		var st = document.createElement('style');
		st.id = 'cb-bcyyt-style';
		st.textContent =
			/* IPv6 完整显示: 放开 nowrap+ellipsis, 允许在任意字符处换行 (手机/电脑通用) */
			'.cb-ip6{white-space:normal !important;word-break:break-all !important;' +
			'overflow:visible !important;text-overflow:clip !important;line-height:1.45 !important;display:inline-block !important;max-width:100% !important}' +
			/* CPU 环可点手势 */
			'.cb-rings .cb-ring:first-child{cursor:pointer}' +
			/* CPU 历史弹层 (Carbon 玻璃风格, 深浅色随 --cb-* 变量) */
			'.cb-cpu-ov{position:fixed;inset:0;z-index:99998;background:rgba(15,23,42,.45);' +
			'-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px);display:flex;' +
			'align-items:center;justify-content:center;padding:16px;animation:cbFade .18s}' +
			'@keyframes cbFade{from{opacity:0}to{opacity:1}}' +
			'.cb-cpu-card{background:var(--cb-card,#fff);border:1px solid var(--cb-border,#e5e5ea);' +
			'border-radius:16px;box-shadow:0 18px 48px rgba(0,0,0,.25);width:min(92vw,560px);' +
			'padding:16px 18px 14px;color:inherit;max-height:88vh;overflow:auto}' +
			'.cb-cpu-head{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:10px}' +
			'.cb-cpu-title{font-weight:600;font-size:14px;display:flex;align-items:center;gap:7px}' +
			'.cb-cpu-x{border:0;background:transparent;font-size:18px;line-height:1;cursor:pointer;' +
			'color:inherit;opacity:.55;padding:4px 8px;border-radius:8px}' +
			'.cb-cpu-x:hover{opacity:1;background:var(--cb-fill,rgba(0,0,0,.06))}' +
			'.cb-cpu-tabs{display:flex;gap:6px;margin-bottom:10px}' +
			'.cb-cpu-tab{border:1px solid var(--cb-border,#e5e5ea);background:transparent;color:inherit;' +
			'font-size:12px;padding:4px 14px;border-radius:99px;cursor:pointer}' +
			'.cb-cpu-tab.on{background:var(--cb-accent,#0a84ff);border-color:var(--cb-accent,#0a84ff);color:#fff}' +
			'.cb-cpu-svg{display:block;width:100%;height:190px}' +
			'.cb-cpu-stats{display:flex;gap:8px;margin-top:10px;flex-wrap:wrap}' +
			'.cb-cpu-st{flex:1;min-width:90px;border:1px solid var(--cb-border,#e5e5ea);border-radius:12px;' +
			'padding:8px 10px;text-align:center}' +
			'.cb-cpu-st small{display:block;opacity:.6;font-size:10px;margin-bottom:2px}' +
			'.cb-cpu-st b{font-size:15px;font-variant-numeric:tabular-nums}';
		document.head.appendChild(st);
	}

	/* ═══════════ ② PPE 环 + 绑定明细 (v2.3 逻辑) ═══════════ */
	function renderPpe(p) {
		var rings = document.querySelector('.cb-res-body .cb-rings');
		if (!rings) return false;
		var p0 = p && p.ppe0 ? p.ppe0 : null;
		var used = p0 ? (p0.t || p0.b || 0) : 0;
		var cap = (p && p.cap) || 4096;
		var pct = Math.min(100, Math.round(used / cap * 100));
		var ring = document.getElementById('cb-ppe-ring');
		if (!ring) {
			ring = document.createElement('div');
			ring.className = 'cb-ring';
			ring.id = 'cb-ppe-ring';
			ring.innerHTML =
				'<svg viewBox="0 0 100 100" aria-hidden="true">' +
				'<circle class="cb-ring-track" cx="50" cy="50" r="42"></circle>' +
				'<circle class="cb-ring-bar" cx="50" cy="50" r="42" style="stroke:var(--cb-blue);stroke-dashoffset:263.89" stroke-dasharray="263.89"></circle>' +
				'</svg>' +
				'<div class="cb-ring-center"><b>0<small>%</small></b></div>' +
				'<div class="cb-ring-label">PPE</div>' +
				'<div class="cb-ring-sub" id="cb-ppe-sub">--</div>';
			ring.title = 'PPE 硬件加速表项占用';
			rings.appendChild(ring);
		}
		ring.querySelector('.cb-ring-center b').innerHTML = pct + '<small>%</small>';
		ring.querySelector('.cb-ring-bar').style.strokeDashoffset = (263.89 * (1 - pct / 100)).toFixed(2);
		var sub = ring.querySelector('#cb-ppe-sub');
		if (sub) {
			sub.textContent = (p && p.hw ? used + ' / ' + cap : '已关闭');
			ring.title = p && p.hw
				? 'PPE 硬件加速 · ' + (p0 ? '表项 ' + p0.t + '/' + cap + ' · 绑定 v4 ' + p0.v4 + ' / v6 ' + p0.v6 : '')
				: 'PPE 硬件加速未启用';
		}
		ring.style.opacity = (p && p.hw) ? '' : '.45';
		renderKvDetail(p);
		return true;
	}

	var lastPpe = null;

	function renderKvDetail(p) {
		if (p) lastPpe = p;
		var kv = document.querySelector('.cb-res-body .cb-kv');
		var loadLi = kv && kv.querySelector('li');
		if (!kv || !loadLi) return;
		var box = document.getElementById('cb-ppe-kv');
		if (!box) {
			box = document.createElement('div');
			box.id = 'cb-ppe-kv';
			box.style.cssText = 'margin-top:6px;border-top:1px solid var(--cb-border);padding-top:6px';
			loadLi.insertAdjacentElement('afterend', box);
		}
		var q = p || lastPpe;
		var q0 = q && q.ppe0 ? q.ppe0 : null;
		var cap = (q && q.cap) || 4096; /* renderKvDetail 独立作用域, 自取容量 */
		if (!q || !q.hw) {
			box.style.display = 'none';
		} else {
			box.style.display = '';
			var rows = [];
			if (q0) {
				/* 表项=占用/容量(与环副标同口径); b(绑定合计)在 IPQ95XX 恒等于 t, 不重复列 */
				rows.push(['PPE 表项',
					q0.t + ' / ' + cap + ' (' + Math.round(q0.t / cap * 100) + '%)' +
					(q.ppe1 && q.ppe1.t ? '  (+PPE1 ' + q.ppe1.t + '/' + cap + ')' : '')]);
				/* v4/v6 = 条目的 IPv4/IPv6 分布(CGI a0/b0); bv4/bv6 才是绑定明细(ba0/bb0) */
				rows.push(['PPE 条目 v4 / v6', q0.v4 + ' / ' + q0.v6]);
				if (q0.bv4 || q0.bv6)
					rows.push(['PPE 绑定 v4 / v6', q0.bv4 + ' / ' + q0.bv6]);
			}
			if (q.host && q.host.c) rows.push(['Host 表占用', q.host.a + ' / ' + q.host.c + ' (' + Math.round(q.host.a / q.host.c * 100) + '%)']);
			if (q.nh && q.nh.c) rows.push(['下一跳表占用', q.nh.a + ' / ' + q.nh.c + ' (' + Math.round(q.nh.a / q.nh.c * 100) + '%)']);
			box.innerHTML = rows.map(function (r) {
				return '<li class="cb-kv-help" style="list-style:none" title="' + esc(r[0]) + '"><span>' + esc(r[0]) + '</span><span class="cb-mono">' + esc(r[1]) + '</span></li>';
			}).join('');
		}
	}

	var kvObserver = null;
	function watchKv() {
		var kv = document.querySelector('.cb-res-body .cb-kv');
		if (!kv || kvObserver) return;
		kvObserver = new MutationObserver(function () {
			if (!document.getElementById('cb-ppe-kv')) renderKvDetail(null);
		});
		kvObserver.observe(kv, { childList: true, subtree: true });
	}

	function refresh() {
		fetch('/cgi-bin/adash', { cache: 'no-store' })
			.then(function (r) { return r.json(); })
			.then(function (d) { fmtOk = renderPpe(d && d.ppe ? d.ppe : null); })
			.catch(function () { });
	}

	/* ═══════════ ③ CPU 历史曲线弹层 ═══════════ */
	var histCache = null, histTs = 0, curRange = 3;

	function fetchHist() {
		if (histCache && Date.now() - histTs < 60000)
			return Promise.resolve(histCache);
		return fetch('/cgi-bin/adash?sys_hist=1', { cache: 'no-store' })
			.then(function (r) { return r.json(); })
			.then(function (d) {
				histCache = (d && d.points) ? d.points : [];
				histTs = Date.now();
				return histCache;
			});
	}

	function hm(t) {
		var d = new Date(t * 1000);
		return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
	}

	function drawChart(svg, pts) {
		var W = svg.clientWidth || 480, H = svg.clientHeight || 190;
		var padX = 10, padT = 14, padB = 24, N = pts.length;
		if (N < 2) { svg.innerHTML = '<text x="50%" y="50%" text-anchor="middle" font-size="12" opacity=".5">暂无数据</text>'; return; }
		var x = function (i) { return padX + i / (N - 1) * (W - 2 * padX); };
		var y = function (v) { return padT + (1 - v / 100) * (H - padT - padB); };
		var peak = 0, sum = 0;
		pts.forEach(function (p) { var v = +p.c || 0; if (v > peak) peak = v; sum += v; });
		var avg = sum / N;
		var line = pts.map(function (p, i) { return x(i).toFixed(1) + ',' + y(+p.c || 0).toFixed(1); }).join(' ');
		var s = '';
		/* 网格: 25/50/75 参考线 */
		[25, 50, 75].forEach(function (g) {
			s += '<line x1="' + padX + '" y1="' + y(g).toFixed(1) + '" x2="' + (W - padX) + '" y2="' + y(g).toFixed(1) + '" stroke="rgba(128,128,128,.18)" stroke-dasharray="3,4"/>';
		});
		/* 面积 + 曲线 */
		s += '<polygon points="' + x(0).toFixed(1) + ',' + (H - padB) + ' ' + line + ' ' + x(N - 1).toFixed(1) + ',' + (H - padB) + '" fill="rgba(10,132,255,.14)"/>';
		s += '<polyline points="' + line + '" fill="none" stroke="var(--cb-blue,#0a84ff)" stroke-width="1.6" stroke-linejoin="round"/>';
		/* 峰值虚线 */
		s += '<line x1="' + padX + '" y1="' + y(peak).toFixed(1) + '" x2="' + (W - padX) + '" y2="' + y(peak).toFixed(1) + '" stroke="rgba(255,159,10,.55)" stroke-dasharray="4,4"/>';
		s += '<text x="' + (W - padX) + '" y="' + Math.max(y(peak) - 4, 10).toFixed(1) + '" text-anchor="end" font-size="10" fill="rgba(255,159,10,.9)">峰值 ' + peak + '%</text>';
		/* 时间轴 4 标 */
		for (var k = 0; k < 4; k++) {
			var idx = Math.round(k / 3 * (N - 1));
			s += '<text x="' + x(idx).toFixed(1) + '" y="' + (H - 8) + '" text-anchor="' + (k === 0 ? 'start' : k === 3 ? 'end' : 'middle') + '" font-size="10" fill="rgba(128,128,128,.8)">' + hm(pts[idx].t) + '</text>';
		}
		s += '<text x="' + padX + '" y="12" font-size="10" fill="rgba(128,128,128,.8)">100%</text>';
		s += '<text x="' + padX + '" y="' + y(50).toFixed(1) + '" dy="-4" font-size="10" fill="rgba(128,128,128,.8)">50%</text>';
		svg.innerHTML = s;
		/* 统计小卡 */
		var last = +pts[N - 1].c || 0;
		var st = document.getElementById('cb-cpu-stats');
		if (st) st.innerHTML =
			'<div class="cb-cpu-st"><small>当前</small><b>' + last + '%</b></div>' +
			'<div class="cb-cpu-st"><small>平均</small><b>' + avg.toFixed(1) + '%</b></div>' +
			'<div class="cb-cpu-st"><small>峰值</small><b>' + peak + '%</b></div>';
	}

	function openModal(range) {
		curRange = range || curRange;
		closeModal(true);
		var ov = document.createElement('div');
		ov.className = 'cb-cpu-ov'; ov.id = 'cb-cpu-modal';
		ov.innerHTML =
			'<div class="cb-cpu-card">' +
			'<div class="cb-cpu-head"><div class="cb-cpu-title">CPU 使用率</div>' +
			'<button class="cb-cpu-x" aria-label="关闭">✕</button></div>' +
			'<div class="cb-cpu-tabs">' +
			'<button class="cb-cpu-tab" data-r="3">3 小时</button>' +
			'<button class="cb-cpu-tab" data-r="24">24 小时</button></div>' +
			'<svg class="cb-cpu-svg" id="cb-cpu-svg"><text x="50%" y="50%" text-anchor="middle" font-size="12" opacity=".5">加载中…</text></svg>' +
			'<div class="cb-cpu-stats" id="cb-cpu-stats"></div>' +
			'</div>';
		document.body.appendChild(ov);
		ov.addEventListener('click', function (e) {
			if (e.target === ov) closeModal();
			else if (e.target.closest('.cb-cpu-x')) closeModal();
			else {
				var tab = e.target.closest('.cb-cpu-tab');
				if (tab) openModal(+tab.dataset.r);
			}
		});
		syncTabs();
		fetchHist().then(function (pts) {
			if (!document.getElementById('cb-cpu-modal')) return;
			if (curRange === 3) pts = pts.slice(-180);
			drawChart(document.getElementById('cb-cpu-svg'), pts);
		}).catch(function () {
			var svg = document.getElementById('cb-cpu-svg');
			if (svg) svg.innerHTML = '<text x="50%" y="50%" text-anchor="middle" font-size="12" opacity=".5">数据加载失败</text>';
		});
	}

	function syncTabs() {
		document.querySelectorAll('.cb-cpu-tab').forEach(function (t) {
			t.classList.toggle('on', +t.dataset.r === curRange);
		});
	}

	function closeModal() {
		var m = document.getElementById('cb-cpu-modal');
		if (m) m.remove();
	}

	/* 事件委托: CPU 环点击 / Esc 关闭 (环被 Carbon 重渲染也不丢) */
	document.addEventListener('click', function (e) {
		var ring = e.target.closest('.cb-rings .cb-ring');
		if (ring && ring.parentElement && ring.parentElement.firstElementChild === ring)
			openModal();
	});
	document.addEventListener('keydown', function (e) {
		if (e.key === 'Escape') closeModal();
	});

	/* ═══════════ 挂载 ═══════════ */
	function isDashPage() {
		/* Carbon 概览页判定: menu-carbon 挂载 dashboard 的唯一页面
		 * (/admin/status/overview)。menu-carbon 需在 footer 执行后已加载。 */
		var dp = (window.L && L.env && L.env.dispatchpath) ? L.env.dispatchpath.join('/') : '';
		return dp.indexOf('status/overview') >= 0 || !!document.querySelector('.cb-dash');
	}

	function mount() {
		var host = document.querySelector('.cb-res-body .cb-rings');
		dbg++;
		if (!host) {
			/* 非概览页: 静默自毁, 不重试不弹提示(footer 下次进页重新注入) */
			if (dbg > 4 && !isDashPage()) {
				window.__carbonBcyytLoaded = false;
				return;
			}
			if (dbg > 60) {
				/* 概览页 24s 仍无资源卡 → 一次性提示后自毁(仅概览页可见) */
				var tip = document.createElement('div');
				tip.id = 'cb-bcyyt-dbg';
				tip.style.cssText = 'position:fixed;right:8px;bottom:8px;z-index:99999;padding:6px 10px;border-radius:8px;background:rgba(15,23,42,.85);color:#7dd3fc;font:11px/1.4 monospace;max-width:260px';
				tip.textContent = 'PPE环: 资源卡未出现 ' + location.pathname;
				document.body.appendChild(tip);
				window.__carbonBcyytLoaded = false;
				return;
			}
			setTimeout(mount, 400);
			return;
		}
		if (document.getElementById('cb-ppe-ring')) return;
		injectStyle();
		refresh();
		watchKv();
		timer = setInterval(function () {
			if (!document.hidden && document.querySelector('.cb-res-body')) {
				refresh();
				watchKv();
			} else if (!document.querySelector('.cb-res-body')) {
				clearInterval(timer);
				if (kvObserver) { kvObserver.disconnect(); kvObserver = null; }
				window.__carbonBcyytLoaded = false;
			}
		}, 15000);
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', mount);
	else
		mount();
})();
