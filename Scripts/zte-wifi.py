#!/usr/bin/python3
# -*- coding: utf-8 -*-
# zte-wifi.py — 中兴 mesh（ZXSLC WebUI 协议）无线客户端采集守护
#
# 功能：
#   登录每个 mesh 节点拉取 vue_client_data（本节点 WiFi 客户端），
#   从主节点拉取 vue_topo_data（mesh 拓扑），合并输出：
#   /tmp/zte-wifi.json
#     {"ts":<unix秒>,
#      "c":{ "<ip>": {"b":"5G","n":"节点名"} },        # WiFi 客户端
#      "n":{ "<ip>": {"r":"主","m":"客厅AX5400 Pro+"} }} # mesh 节点本身
#   失败时保留上次数据（只更新 ts.err 标记）。
#
# 协议（ZXSLC WebUI，巡天/问天/晴天系）：
#   1) GET /?_type=loginsceneData&_tag=login_token_json → {logintoken,_sessionToken}
#   2) Password = sha256(密码 + logintoken)（小写 hex）
#   3) POST /?_type=loginData&_tag=login_entry
#      Username=admin&Password=<hash>&action=login&Frm_Logintoken=&captchaCode=&_sessionTOKEN=<_sessionToken>
#      响应 login_need_refresh=true 即成功，Set-Cookie SID
#   4) GET /?_type=vueData&_tag=vue_client_data&_=<ms>
#   5) GET /?_type=vueData&_tag=vue_topo_data&Action=GetALLAP&_=<ms>（仅主节点，JSON）
#
# 配置 /etc/zte-wifi.conf（root:600）：
#   {"password":"...","nodes":[{"ip":"192.168.10.101","name":"客厅","topo":true},
#                               {"ip":"192.168.10.118","name":"晴天"}],
#    "bands":{"wlan2":"2.4G","wlan4":"5G"},"interval":30}

import hashlib
import http.cookiejar
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

CONF = '/etc/zte-wifi.conf'
OUT = '/tmp/zte-wifi.json'
UA = {'User-Agent': 'Mozilla/5.0'}
TIMEOUT = 6


class Node:
    def __init__(self, ip, name='', topo=False):
        self.ip = ip
        self.base = 'http://' + ip
        self.name = name or ip
        self.topo = topo
        self.cj = http.cookiejar.CookieJar()

    def _op(self):
        return urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.cj))

    def get(self, path):
        req = urllib.request.Request(self.base + path, headers=UA)
        with self._op().open(req, timeout=TIMEOUT) as r:
            return r.read().decode('utf-8', 'ignore')

    def post(self, path, data):
        body = '&'.join('%s=%s' % (k, urllib.parse.quote(str(v), safe=''))
                        for k, v in data.items()).encode()
        req = urllib.request.Request(self.base + path, data=body, headers=dict(
            UA, **{'Content-Type': 'application/x-www-form-urlencoded'}))
        with self._op().open(req, timeout=TIMEOUT) as r:
            return r.read().decode('utf-8', 'ignore')

    def login(self, pw):
        t = json.loads(self.get('/?_type=loginsceneData&_tag=login_token_json'))
        h = hashlib.sha256((pw + t.get('logintoken', '')).encode()).hexdigest()
        r = json.loads(self.post('/?_type=loginData&_tag=login_entry', {
            'Username': 'admin', 'Password': h, 'action': 'login',
            'Frm_Logintoken': '', 'captchaCode': '',
            '_sessionTOKEN': t.get('_sessionToken', '')}))
        return r.get('login_need_refresh') is True

    def clients(self):
        ts = int(time.time() * 1000)
        x = self.get('/?_type=vueData&_tag=vue_client_data&_=%d' % ts)
        seg = re.search(r'<OBJ_CLIENTS_ID>(.*?)</OBJ_CLIENTS_ID>', x, re.S)
        out = []
        if not seg:
            return out
        for ins in re.findall(r'<Instance>(.*?)</Instance>', seg.group(1), re.S):
            d = dict(re.findall(r'<ParaName>([^<]+)</ParaName>'
                                r'<ParaValue>([^<]*)</ParaValue>', ins))
            out.append(d)
        return out

    def topology(self):
        ts = int(time.time() * 1000)
        s = self.get('/?_type=vueData&_tag=vue_topo_data&Action=GetALLAP&_=%d' % ts)
        d = json.loads(s)
        return d.get('apData') or {}


def xml_unescape(s):
    return (s.replace('&#32;', ' ').replace('&amp;', '&')
             .replace('&quot;', '"').replace('&lt;', '<').replace('&gt;', '>'))


TEMPLATE = {
    'password': '改为中兴路由器Web管理密码',
    'nodes': [
        {'ip': '192.168.10.101', 'name': '主节点名', 'topo': True},
        {'ip': '192.168.10.118', 'name': '子节点名'}
    ],
    'bands': {'wlan2': '2.4G', 'wlan4': '5G'},
    'interval': 30,
}


def main():
    once = '-1' in sys.argv or '--once' in sys.argv
    try:
        with open(CONF) as f:
            conf = json.load(f)
    except (OSError, ValueError):
        # 无配置：生成模板提示用户填写（不崩溃，守护可被 procd 重启）
        try:
            with open(CONF + '.template', 'w') as f:
                json.dump(TEMPLATE, f, ensure_ascii=False, indent=2)
        except OSError:
            pass
        sys.stderr.write('zte-wifi: 缺少 %s，已生成 .template\n' % CONF)
        return 1
    pw = conf['password']
    bands = conf.get('bands') or {'wlan2': '2.4G', 'wlan4': '5G'}
    interval = max(10, int(conf.get('interval', 30)))
    nodes = [Node(n['ip'], n.get('name', ''), n.get('topo', False))
             for n in conf.get('nodes', [])]
    if not nodes:
        sys.stderr.write('zte-wifi: no nodes configured\n')
        return 1

    last = {'ts': 0, 'c': {}, 'n': {}}
    while True:
        cur = {'ts': int(time.time()), 'c': {}, 'n': dict(last.get('n') or {})}
        ok_any = False
        for nd in nodes:
            try:
                if not nd.login(pw):
                    continue
                ok_any = True
                for d in nd.clients():
                    ip = d.get('IPAddress', '')
                    ifc = d.get('Interface', '')
                    if ip and ifc.startswith('wlan'):
                        cur['c'][ip] = {'b': bands.get(ifc, ifc),
                                        'n': nd.name}
                if nd.topo:
                    for k, v in nd.topology().items():
                        if k == 'MGET_INST_NUM':
                            continue
                        ip = v.get('IpAddr', '')
                        if ip:
                            cur['n'][ip] = {
                                'r': '主' if v.get('role') == 'controller' else '子',
                                'm': xml_unescape(v.get('DeviceName')
                                                  or v.get('ModelName', ''))}
            except Exception:
                pass  # 单节点失败不影响其他节点；保留旧数据

        if ok_any or not last.get('ts'):
            last = cur
        else:
            last['ts'] = cur['ts']  # 全失败：保旧数据只推进时间戳

        tmp = OUT + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(last, f, ensure_ascii=False, separators=(',', ':'))
        os.chmod(tmp, 0o644)
        os.replace(tmp, OUT)

        if once:
            break
        time.sleep(interval)
    return 0


if __name__ == '__main__':
    sys.exit(main())
