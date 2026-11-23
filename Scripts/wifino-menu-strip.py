#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# WIFI-NO 线 LuCI 无线菜单物理摘除（由 Scripts/Handles.sh 在编译期调用，仅 *WIFI-NO* 配置）
# 用法：wifino-menu-strip.py <menu.json> [menu.json ...]
#
# 背景：WIFI-NO 线无线栈全剥离，LuCI 菜单条目带 uci depends（无 @wifi-device 应自动隐藏），
#      但 sysupgrade 保留设置会把旧固件 wireless 配置恢复进来，且 Snapshot 版 depends 链
#      有失效案例（2026-11-23 IPQ95XX-WIFI-NO 实机复现空壳菜单，点击报错）。
#      直接从 menu.d 定义中删除条目，一劳永逸。
# 摘除条目：
#   admin/network/wireless        网络 → 无线
#   admin/status/channel_analysis 状态 → 信道分析
#   admin/status/realtime/wireless 实时统计 → 无线
import json, sys

DROP = [
	'admin/network/wireless',
	'admin/status/channel_analysis',
	'admin/status/realtime/wireless',
]

for path in sys.argv[1:]:
	d = json.load(open(path, encoding='utf-8'))
	n = 0
	for k in DROP:
		if k in d:
			del d[k]
			n += 1
	if n:
		with open(path, 'w', encoding='utf-8') as f:
			json.dump(d, f, ensure_ascii=False, indent='\t')
			f.write('\n')
	print(f'wifino-menu: {path.rsplit("/", 1)[-1]} removed {n} entr{"y" if n == 1 else "ies"}')
