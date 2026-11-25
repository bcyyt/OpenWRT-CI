#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 bcyyt
#
# Release 精简：4 条编译线每线只保留 2 个最新固件 Release
# 规则：每条线内先保住"每个配置各 1 个最新"（防止某配置被清零），
#       再按时间倒序补足到 2 个；其余 Release 连同 tag 一并删除。
# 依赖：环境变量 GH_TOKEN（需 repo 删除权限）、GITHUB_REPOSITORY

import json
import os
import re
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
REPO = os.environ.get("GITHUB_REPOSITORY", "bcyyt/OpenWRT-CI")
TOKEN = os.environ.get("GH_TOKEN", "")
KEEP_PER_LINE = 2

# 线归属：tag 前缀 → 编译线（与 .github/workflows/*.yml 的 matrix 对应）
LINE_RULES = [
    ("QCB-ARGON",    re.compile(r"^IPQ95XX(-WIFI-NO)?-VIKINGYFY-owrt-argon-")),
    ("QCB-ALL",      re.compile(r"^IPQ95XX(-WIFI-NO)?-VIKINGYFY-owrt-vantage-")),
    ("MTK-S20P-612", re.compile(r"^MEDIATEK-S20P-WIFI-NO-chasey-dev-25\.12-argon-")),
    ("MTK-ALL",      re.compile(r"^MEDIATEK-(WIFI-YES|WIFI-NO)-VIKINGYFY-owrt-vantage-")),
]

# 配置子组：去掉尾部时间戳后即配置前缀
TS_SUFFIX = re.compile(r"-\d{2}\.\d{2}\.\d{2}-\d{2}\.\d{2}\.\d{2}$")


def gh(method, path, data=None):
    req = urllib.request.Request(
        f"{API}/repos/{REPO}/{path}",
        method=method,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
        },
        data=json.dumps(data).encode() if data is not None else None,
    )
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read()
            return r.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def list_releases():
    rels, page = [], 1
    while True:
        code, batch = gh("GET", f"releases?per_page=100&page={page}")
        if code != 200 or not batch:
            break
        rels.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return rels


def line_of(tag):
    for name, pat in LINE_RULES:
        if pat.match(tag):
            return name
    return None


def main():
    if not TOKEN:
        sys.exit("GH_TOKEN 未设置")
    rels = list_releases()
    print(f"现有 Release {len(rels)} 个")

    by_line = {}
    for r in rels:
        if r.get("draft"):
            continue
        line = line_of(r["tag_name"] or "")
        if line:
            by_line.setdefault(line, []).append(r)
        else:
            print(f"跳过（不匹配任何线）: {r['tag_name']}")

    to_delete = []
    for line, items in sorted(by_line.items()):
        # 最新在前
        items.sort(key=lambda r: r["created_at"], reverse=True)
        config_key = lambda r: TS_SUFFIX.sub("", r["tag_name"])
        keep, seen_cfg = [], set()
        # 1) 每个配置各保 1 个最新
        for r in items:
            cfg = config_key(r)
            if cfg not in seen_cfg:
                seen_cfg.add(cfg)
                keep.append(r)
        # 2) 按时间补足到 KEEP_PER_LINE
        for r in items:
            if len(keep) >= KEEP_PER_LINE:
                break
            if r not in keep:
                keep.append(r)
        keep_ids = {r["id"] for r in keep}
        drop = [r for r in items if r["id"] not in keep_ids]
        print(f"{line}: 保留 {[r['tag_name'] for r in keep]}")
        to_delete.extend(drop)

    if not to_delete:
        print("无需删除")
        return

    ok = fail = 0
    for r in to_delete:
        code, _ = gh("DELETE", f"releases/{r['id']}")
        if code in (204, 200):
            ok += 1
            # 连同 tag 一起删（tag 名与 release 名相同）
            gh("DELETE", f"git/refs/tags/{r['tag_name']}")
            print(f"已删除: {r['tag_name']}")
        else:
            fail += 1
            print(f"删除失败({code}): {r['tag_name']}")
    print(f"完成：删 {ok} 个" + (f"，失败 {fail} 个" if fail else ""))


if __name__ == "__main__":
    main()
