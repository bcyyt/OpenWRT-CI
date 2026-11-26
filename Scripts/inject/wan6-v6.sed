# wan6 IPv6 双坑修复 (2026-11-26, TROUBLESHOOTING 坑4) — 零tab, 防"洗tab"事故
# 坑A: 删 pppoe 分支的 wan.ipv6='1' (wan_6 动态接口崩溃循环源头, pppd 仍协商 IPv6CP)
/set network\.\$1\.ipv6='1'/d
# 坑B: dhcp/pppoe 两分支生成的 wan6 补 reqaddress='try' (odhcp6c 需 -Ntry 才上报 SLAAC 地址)
s|\(set network\.\${1}6\.proto='dhcpv6'\)|\1\n\t\t\t\t\tset network\.\${1}6\.reqaddress='try'|
