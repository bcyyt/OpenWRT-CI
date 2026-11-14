#!/usr/bin/python3
# -*- coding: utf-8 -*-
# zte-wifi.py — 中兴 mesh（ZXSLC WebUI 协议）无线客户端采集守护 v3
#
# 功能：
#   登录每个 mesh 节点拉取 vue_client_data（本节点 WiFi 客户端），
#   从主节点拉取 vue_topo_data（mesh 拓扑），合并输出：
#   /tmp/zte-wifi.json
#     {"ts":<unix秒>,
#      "c":{ "<ip>": {"b":"5G","n":"节点名"} },        # WiFi 客户端
#      "n":{ "<ip>": {"r":"主","m":"客厅AX5400 Pro+"} }} # mesh 节点本身
#   失败时保留上次数据（只更新 ts）。
#
# 配置（UCI /etc/config/zte-wifi，LuCI「系统 → ZTE Mesh 无线」维护）：
#   config main 'main'
#       option password '...'      # 中兴 Web 管理密码（必填，未填时待机）
#       option interval '30'       # 采集间隔秒（≥10）
#   config node
#       option ip '192.168.10.101'  # 节点管理 IP
#       option name '客厅...'      # 节点显示名
#       option topo '1'            # 主节点（额外拉拓扑）
#   每轮检查配置 mtime，LuCI 保存后无需重启即生效；未配置密码时守护待机
#   （不退出，配置出现后自动开始）。旧版 JSON /etc/zte-wifi.conf 自动回退兼容。
#
# 协议（ZXSLC WebUI，巡天/问天/晴天系）：
#   1) GET /?_type=loginsceneData&_tag=login_token_json → {logintoken,_sessionToken}
#   2) Password = sha256(密码 + logintoken)（小写 hex）
#   3) POST /?_type=loginData&_tag=login_entry
#      Username=admin&Password=<hash>&action=login&Frm_Logintoken=&captchaCode=&_sessionTOKEN=<_sessionToken>
#      响应 login_need_refresh=true 即成功，Set-Cookie SID
#   4) GET /?_type=vueData&_tag=vue_client_data&_=<ms>
#   5) GET /?_type=vueData&_tag=vue_topo_data&Action=GetALLAP&_=<ms>（仅主节点，JSON）

import hashlib
import http.cookiejar
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

CONF_UCI = '/etc/config/zte-wifi'
CONF_JSON = '/etc/zte-wifi.conf'  # 旧版 JSON（UCI 无密码时回退）
OUT = '/tmp/zte-wifi.json'
UA = {'User-Agent': 'Mozilla/5.0'}
TIMEOUT = 6
DEFAULT_BANDS = {'wlan2': '2.4G', 'wlan4': '5G'}


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


def uci_unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
        v = v[1:-1]
    return (v.replace("\\'", "'").replace('\\"', '"')
              .replace('\\\\', '\\'))


def load_conf():
    """读 UCI 配置；无密码时回退旧版 JSON。返回 dict 或 None。"""
    pw = ''
    interval = 30
    nodes = []
    try:
        cur = None
        with open(CONF_UCI) as f:
            for line in f:
                line = line.strip()
                m = re.match(r"^config\s+(\S+)", line)
                if m:
                    if cur and cur.get('ip'):
                        nodes.append(cur)
                    cur = {'type': m.group(1)}
                    continue
                if cur is None:
                    continue
                m = re.match(r"^option\s+(\S+)\s+(.+)$", line)
                if not m:
                    continue
                k, v = m.group(1), uci_unquote(m.group(2))
                if cur.get('type') == 'main':
                    if k == 'password':
                        pw = v
                    elif k == 'interval':
                        try:
                            interval = max(10, int(v))
                        except ValueError:
                            pass
                elif cur.get('type') == 'node':
                    if k == 'ip':
                        cur['ip'] = v
                    elif k == 'name':
                        cur['name'] = v
                    elif k == 'topo':
                        cur['topo'] = v in ('1', 'true', 'on', 'yes')
        if cur and cur.get('ip'):
            nodes.append(cur)
    except OSError:
        pass

    if pw:
        return {'password': pw, 'interval': interval,
                'nodes': [Node(n['ip'], n.get('name', ''), n.get('topo', False))
                          for n in nodes if n.get('ip')]}

    # 回退：旧版 JSON（迁移前）
    try:
        with open(CONF_JSON) as f:
            j = json.load(f)
        return {'password': j.get('password', ''),
                'interval': max(10, int(j.get('interval', 30))),
                'nodes': [Node(n['ip'], n.get('name', ''), n.get('topo', False))
                          for n in j.get('nodes', []) if n.get('ip')]}
    except (OSError, ValueError, KeyError, TypeError):
        return None


RATE_MULT = {'bps': 1, 'Kbps': 1e3, 'Mbps': 1e6, 'Gbps': 1e9}


def parse_rate(s):
    """'123.4Kbps'/'0bps' -> bps 整数。"""
    m = re.match(r'^([\d.]+)\s*(bps|Kbps|Mbps|Gbps)$', (s or '').strip())
    if m:
        return int(float(m.group(1)) * RATE_MULT.get(m.group(2), 1))
    return parse_num(s) or 0


def parse_num(s):
    try:
        return int(float(s))
    except Exception:
        return None


def collect(conf):
    """跑一轮采集，返回 (cur, ok_any)。"""
    cur = {'ts': int(time.time()), 'c': {}, 'n': {}}
    ok_any = False
    for nd in conf['nodes']:
        try:
            if not nd.login(conf['password']):
                continue
            ok_any = True
            for d in nd.clients():
                ip = d.get('IPAddress', '')
                ifc = d.get('Interface', '')
                if ip and ifc.startswith('wlan'):
                    cur['c'][ip] = {
                        'b': DEFAULT_BANDS.get(ifc, ifc),
                        'n': nd.name,
                        'm': (xml_unescape(d.get('AliasName', ''))
                              or xml_unescape(d.get('HostName', '')) or ''),
                        'mac': d.get('MACAddress', ''),
                        'ur': parse_rate(d.get('UpRate')),
                        'dr': parse_rate(d.get('DownRate')),
                        'ut': parse_num(d.get('UpThroughput')),
                        'dt': parse_num(d.get('DownThroughput')),
                        'on': parse_num(d.get('OnlineDuration')),
                        'lc': xml_unescape(d.get('LastConnection', '')),
                    }
            if nd.topo:
                for k, v in nd.topology().items():
                    if k == 'MGET_INST_NUM':
                        continue
                    ip = v.get('IpAddr', '')
                    if ip:
                        cur['n'][ip] = {
                            'r': '主' if v.get('role') == 'controller' else '子',
                            'm': xml_unescape(v.get('DeviceName')
                                              or v.get('ModelName', '')),
                            'md': v.get('ModelName', ''),
                            'sv': v.get('SoftwareVer', ''),
                            'at': v.get('AccessType', ''),
                            'ls': v.get('LinkSpeed', ''),
                            'ms': v.get('MeshStatus', '')}
        except Exception:
            pass  # 单节点失败不影响其他节点；保留旧数据
    return cur, ok_any


def main():
    once = '--once' in sys.argv
    last = {'ts': 0, 'c': {}, 'n': {}}
    conf_mtime = object()  # 强制首轮加载
    conf = None
    warned = False
    while True:
        try:
            mt = os.stat(CONF_UCI).st_mtime
        except OSError:
            mt = None
        if mt != conf_mtime:
            conf = load_conf()
            conf_mtime = mt
            warned = False

        if conf and conf['password'] and conf['nodes']:
            cur, ok_any = collect(conf)
            if ok_any or not last.get('ts'):
                last = cur
            else:
                last['ts'] = cur['ts']  # 全失败：保旧数据只推进时间戳
            tmp = OUT + '.tmp'
            with open(tmp, 'w') as f:
                json.dump(last, f, ensure_ascii=False, separators=(',', ':'))
            os.chmod(tmp, 0o644)
            os.replace(tmp, OUT)
        elif not warned:
            sys.stderr.write('zte-wifi: 未配置密码/节点'
                             '（LuCI → 系统 → ZTE Mesh 无线），待机中\n')
            sys.stderr.flush()
            warned = True

        if once:
            return 0 if (conf and conf['password']) else 1
        time.sleep(conf['interval'] if conf else 30)
    return 0


if __name__ == '__main__':
    sys.exit(main())
