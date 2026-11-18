#!/usr/bin/python3
# -*- coding: utf-8 -*-
# zte-wifi.py — 中兴 mesh（ZXSLC WebUI 协议）无线客户端采集守护 v4
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
# v4 自动发现：
#   · 零配置引导：只填密码不配节点 → 从 ARP 表 + DHCP 租约取候选，
#     用 login_token_json 敲门识别 ZXSLC 设备（其他设备 404/超时），
#     登录成功后拉拓扑一次性获得全部 mesh 节点（含主/子角色）。
#   · 拓扑反哺：每轮将拓扑结果同步回 UCI 节点表 —— 新节点自动加入、
#     主节点标记自动校正、连续 STALE_FAILS 轮失败且不在拓扑中的节点自动移除。
#   · 韧性：配置的拓扑源全部失败时，每 5 分钟从任一在线节点补拉一次拓扑，
#     避免"主节点一挂 n 段全空"。
#   · 探测只使用守护常规端点（login_token_json / login / vue_client_data /
#     vue_topo_data），绝不请求未知页面（2026-11-18 教训：未知 _tag 可致节点崩溃）。
#   · 选项 autodiscover '0' 关闭拓扑反哺；scan '0' 关闭零配置引导扫描（默认全开）。
#
# 配置（UCI /etc/config/zte-wifi，LuCI「系统 → ZTE Mesh 无线」维护）：
#   config main 'main'
#       option password '...'      # 中兴 Web 管理密码（必填，未填时待机）
#       option interval '30'       # 采集间隔秒（≥10）
#       option autodiscover '1'    # v4：拓扑反哺节点表（默认开）
#       option scan '1'            # v4：零配置引导扫描（默认开）
#   config node
#       option ip '192.168.10.101'  # 节点管理 IP（可留空由自动发现填写）
#       option name '客厅...'      # 节点显示名（自动发现用拓扑 DeviceName）
#       option topo '1'            # 主节点（额外拉拓扑；角色由拓扑自动校正）
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
#   5) GET /?_type=vueData&_tag=vue_topo_data&Action=GetALLAP&_=<ms>（主节点，JSON）

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

# v4 自动发现参数
SCAN_PER_CYCLE = 10          # 引导期每轮最多探测候选数
PROBE_TIMEOUT = 2.5          # 敲门超时（秒）
PROBE_TTL = 600              # 候选否定结果缓存（秒），避免反复骚扰非中兴设备
STALE_FAILS = 3              # 连续失败 N 轮且不在拓扑 → 移除
TOPO_RETRY = 300             # 拓扑兜底补拉间隔（秒）


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


def probe_zxslc(ip):
    """敲门识别：只有 ZXSLC WebUI 会对 login_token_json 返回 JSON。"""
    try:
        req = urllib.request.Request(
            'http://%s/?_type=loginsceneData&_tag=login_token_json' % ip,
            headers=UA)
        with urllib.request.urlopen(req, timeout=PROBE_TIMEOUT) as r:
            return 'logintoken' in r.read().decode('utf-8', 'ignore')
    except Exception:
        return False


def lan_candidates():
    """LAN 候选 IP：内核 ARP 表（已完成解析的）+ dnsmasq 租约。"""
    ips = set()
    try:
        with open('/proc/net/arp') as f:
            for ln in f.read().splitlines()[1:]:
                p = ln.split()
                # flags 0x2 = 完整条目；FAILED/Incomplete 不进候选
                if len(p) >= 4 and p[2] == '0x2':
                    ips.add(p[0])
    except OSError:
        pass
    try:
        with open('/tmp/dhcp.leases') as f:
            for ln in f:
                p = ln.split()
                if len(p) >= 3:
                    ips.add(p[2])
    except OSError:
        pass
    return sorted(ips)


def parse_topology_nodes(ap):
    """apData → {ip: {'name': 显示名, 'main': 是否主节点}}"""
    out = {}
    for k, v in (ap or {}).items():
        if k == 'MGET_INST_NUM' or not isinstance(v, dict):
            continue
        ip = v.get('IpAddr', '')
        if ip:
            out[ip] = {
                'name': (xml_unescape(v.get('DeviceName')
                                      or v.get('ModelName', '')) or ip),
                'main': v.get('role') == 'controller',
            }
    return out


def uci_safe(s):
    return (s or '').replace("'", '').replace('"', '').replace('\n', ' ').strip()


def save_nodes_uci(nodes):
    """只重写 node 段；main 段及注释原样保留（原子替换）。"""
    try:
        head = []
        with open(CONF_UCI) as f:
            for ln in f:
                if re.match(r'^\s*config\s+node', ln):
                    break
                head.append(ln)
        if not head:
            head = ["config main 'main'\n"]
    except OSError:
        head = ["config main 'main'\n"]
    body = ['\n']
    for nd in nodes:
        body.append('config node\n')
        body.append("\toption ip '%s'\n" % nd.ip)
        name = uci_safe(nd.name)
        if name and name != nd.ip:
            body.append("\toption name '%s'\n" % name)
        if nd.topo:
            body.append("\toption topo '1'\n")
        body.append('\n')
    tmp = CONF_UCI + '.tmp'
    with open(tmp, 'w') as f:
        f.writelines(head + body)
    os.replace(tmp, CONF_UCI)


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
    enabled = True
    autodiscover = True
    scan = True
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
                    elif k == 'enabled':
                        enabled = v not in ('0', 'off', 'false', 'no')
                    elif k == 'autodiscover':
                        autodiscover = v not in ('0', 'off', 'false', 'no')
                    elif k == 'scan':
                        scan = v not in ('0', 'off', 'false', 'no')
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
        return {
        'enabled': enabled,'password': pw, 'interval': interval,
                'autodiscover': autodiscover, 'scan': scan,
                'nodes': [Node(n['ip'], n.get('name', ''), n.get('topo', False))
                          for n in nodes if n.get('ip')]}

    # 回退：旧版 JSON（迁移前）
    try:
        with open(CONF_JSON) as f:
            j = json.load(f)
        return {'password': j.get('password', ''),
                'interval': max(10, int(j.get('interval', 30))),
                'autodiscover': True, 'scan': True,
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


def collect(conf, topo_fallback_ts=[0]):
    """跑一轮采集，返回 (cur, ok_any, ap, ok_map)。"""
    cur = {'ts': int(time.time()), 'c': {}, 'n': {}}
    ok_any = False
    ap = {}
    ok_map = {}
    for nd in conf['nodes']:
        try:
            if not nd.login(conf['password']):
                continue
            ok_any = True
            ok_map[nd.ip] = True
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
                t = nd.topology()
                if t:
                    ap.update(t)
        except Exception:
            pass  # 单节点失败不影响其他节点；保留旧数据

    # v4 韧性：拓扑源全失败 → 每 TOPO_RETRY 秒从任一在线节点补拉一次
    if not ap and ok_map and time.time() - topo_fallback_ts[0] >= TOPO_RETRY:
        topo_fallback_ts[0] = time.time()
        for nd in conf['nodes']:
            if ok_map.get(nd.ip):
                try:
                    t = nd.topology()
                    if t:
                        ap = t
                        break
                except Exception:
                    pass

    if ap:
        for k, v in ap.items():
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
    return cur, ok_any, ap, ok_map


def sync_nodes(conf, ap, fails):
    """拓扑 → 节点表同步。返回是否变化（调用方负责落盘）。"""
    disc = parse_topology_nodes(ap)
    if not disc:
        return False
    changed = False
    byip = {nd.ip: nd for nd in conf['nodes']}
    # 新节点加入（名字用拓扑 DeviceName）
    for ip, info in disc.items():
        if ip not in byip:
            conf['nodes'].append(Node(ip, info['name'], info['main']))
            changed = True
    # 已知节点角色校正
    for nd in conf['nodes']:
        info = disc.get(nd.ip)
        if info and bool(nd.topo) != info['main']:
            nd.topo = info['main']
            changed = True
    # 失联清理：连续 STALE_FAILS 轮失败 且 拓扑中不存在
    keep = []
    for nd in conf['nodes']:
        if fails.get(nd.ip, 0) >= STALE_FAILS and nd.ip not in disc:
            changed = True
            continue
        keep.append(nd)
    conf['nodes'] = keep
    return changed


def bootstrap_scan(conf, probed):
    """零配置引导：敲门候选 → 登录 → 拓扑一次性拿全 mesh。"""
    now = time.time()
    cands = [ip for ip in lan_candidates()
             if now - probed.get(ip, 0) >= PROBE_TTL]
    found = []
    ap = {}
    for ip in cands[:SCAN_PER_CYCLE]:
        probed[ip] = now
        if not probe_zxslc(ip):
            continue
        n = Node(ip)
        try:
            if not n.login(conf['password']):
                continue  # 中兴设备但密码不符（非自家设备），跳过
            try:
                t = n.topology()
            except Exception:
                t = {}
            if t:
                ap = t
                break
            found.append(n)  # 子节点：先记下，等拓扑校正
        except Exception:
            pass
    if ap:
        disc = parse_topology_nodes(ap)
        conf['nodes'] = [Node(ip, i['name'], i['main'])
                         for ip, i in disc.items()]
        save_nodes_uci(conf['nodes'])
        _log('自动发现 %d 个 mesh 节点: %s' % (
            len(conf['nodes']),
            ', '.join('%s(%s)' % (nd.name, '主' if nd.topo else '子')
                      for nd in conf['nodes'])))
    elif found:
        found[0].topo = True  # 暂作拓扑源，角色由后续拓扑校正
        conf['nodes'] = found
        save_nodes_uci(found)
        _log('自动发现 %d 个节点（单点模式，待拓扑校正）: %s' % (
            len(found), ', '.join(nd.ip for nd in found)))


def _log(msg):
    sys.stderr.write('zte-wifi: %s\n' % msg)
    sys.stderr.flush()


def main():
    once = '--once' in sys.argv
    last = {'ts': 0, 'c': {}, 'n': {}}
    conf_mtime = object()  # 强制首轮加载
    conf = None
    warned = False
    fails = {}     # ip → 连续失败轮数
    probed = {}    # ip → 上次敲门时间（否定缓存）
    while True:
        try:
            mt = os.stat(CONF_UCI).st_mtime
        except OSError:
            mt = None
        if mt != conf_mtime:
            conf = load_conf()
            conf_mtime = mt
            warned = False

        if conf and not conf.get('enabled', True):
            if not warned:
                _log('总开关关闭（LuCI → 系统 → ZTE Mesh 无线），待机中')
                warned = True
        elif conf and conf['password'] and conf['nodes']:
            cur, ok_any, ap, ok_map = collect(conf)
            for nd in conf['nodes']:
                if ok_map.get(nd.ip):
                    fails[nd.ip] = 0
                else:
                    fails[nd.ip] = fails.get(nd.ip, 0) + 1
            if ok_any or not last.get('ts'):
                last = cur
            else:
                last['ts'] = cur['ts']  # 全失败：保旧数据只推进时间戳
            tmp = OUT + '.tmp'
            with open(tmp, 'w') as f:
                json.dump(last, f, ensure_ascii=False, separators=(',', ':'))
            os.chmod(tmp, 0o644)
            os.replace(tmp, OUT)
            # v4 拓扑反哺
            if conf.get('autodiscover', True) and ap:
                if sync_nodes(conf, ap, fails):
                    save_nodes_uci(conf['nodes'])
                    _log('节点表已同步（自动发现）: %s' % ', '.join(
                        '%s(%s)' % (nd.name, '主' if nd.topo else '子')
                        for nd in conf['nodes']))
        elif (conf and conf['password'] and not conf['nodes']
              and conf.get('scan', True)):
            # v4 零配置引导
            bootstrap_scan(conf, probed)
            if once:
                return 0 if conf['nodes'] else 1
        elif not warned:
            _log('未配置密码（LuCI → 系统 → ZTE Mesh 无线），待机中'
                 if not conf else '未配置密码/节点，待机中')
            warned = True

        if once:
            return 0 if (conf and conf['password']) else 1
        time.sleep(conf['interval'] if conf else 30)
    return 0


if __name__ == '__main__':
    sys.exit(main())
