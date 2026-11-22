'use strict';
'require view';
'require form';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('uhttpd', _('HTTP(S) Access'),
			_('监听格式：IPv4 写 0.0.0.0:端口，IPv6 写 [::]:端口。保存后 uHTTPd 自动重启。'));

		s = m.section(form.NamedSection, 'main', 'uhttpd', _('主实例'));
		s.addremove = false;

		o = s.option(form.DynamicList, 'listen_http', _('HTTP 监听'));
		o.placeholder = '[::]:2000';
		o.rmempty = true;

		o = s.option(form.DynamicList, 'listen_https', _('HTTPS 监听'));
		o.placeholder = '[::]:2001';
		o.rmempty = true;

		o = s.option(form.Flag, 'redirect_https', _('重定向到 HTTPS'));
		o.rmempty = false;

		s = m.section(form.NamedSection, 'luci', 'uhttpd', _('LuCI 界面实例'));
		s.addremove = false;

		o = s.option(form.DynamicList, 'listen_http', _('HTTP 监听'));
		o.placeholder = '[::]:80';
		o.rmempty = true;

		o = s.option(form.DynamicList, 'listen_https', _('HTTPS 监听'));
		o.placeholder = '[::]:443';
		o.rmempty = true;

		o = s.option(form.Flag, 'redirect_https', _('重定向到 HTTPS'));
		o.rmempty = false;

		return m.render();
	}
});
