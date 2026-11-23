#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# PPE 单引擎显示修正（由 Scripts/Handles.sh 在编译期调用，仅 IPQ95XX 线注入）
# 用法：vantage-ppe-patch.py <overview.js>
#
# 背景：IPQ95XX 6.18 上游 qcom_ppe 驱动只暴露单 PPE 引擎
#      （debugfs 单目录 /sys/kernel/debug/ppe/，无 ppe0/ppe1 分目录），
#      上游 Vantage 仪表盘固定渲染 PPE0+PPE1 两个槽位，单引擎设备会
#      常驻一行 "PPE1: 0 (绑定v4:0 / v6:0)"。
# 修正：PPE1 槽位改为条件渲染——
#      - 数据源 ppe1.t > 0（双引擎设备）→ 保持 PPE0 + PPE1 原样
#      - ppe1 无数据（单引擎）→ 只渲染一个 "PPE" 槽位
# 幂等：已打过补丁（存在 part('PPE', d.ppe0)）时跳过；锚点缺失时非致命告警
import re, sys

path = sys.argv[1]
src = open(path, encoding='utf-8').read()

if "part('PPE', d.ppe0)" in src:
    print('vantage-ppe: already patched, skip')
    sys.exit(0)

pat = re.compile(r"part\('PPE0',\s*d\.ppe0\)\s*\+\s*'\s*'\s*\+\s*part\('PPE1',\s*d\.ppe1\)")
if not pat.search(src):
    print('vantage-ppe: WARN anchor not found (upstream overview.js changed?), skip')
    sys.exit(0)

src, n = pat.subn(
    "(d.ppe1 && d.ppe1.t ? part('PPE0', d.ppe0) + ' ' + part('PPE1', d.ppe1) : part('PPE', d.ppe0))",
    src, count=1)
open(path, 'w', encoding='utf-8').write(src)
print(f'vantage-ppe: PPE1 slot now conditional ({n} site patched)')
