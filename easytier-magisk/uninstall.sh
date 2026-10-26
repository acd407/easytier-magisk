MODDIR=${0%/*}

# 先停掉后台循环和 easytier-core，否则 check_disable/check_magic_dns 会继续跑
pkill -f "$MODDIR/run.sh" 2>/dev/null
pkill -f "$MODDIR/easytier/" 2>/dev/null

# 清理魔法 DNS 重定向规则，避免残留规则把 App 的 DNS 指向已经不存在的魔法 DNS
# 跳转规则带 -m string（只匹配 *.et.net），所以按序号删，新旧格式都能删干净
IT=/system/bin/iptables
nums=$($IT -t nat -L OUTPUT --line-numbers -n 2>/dev/null |
    awk '$1 ~ /^[0-9]+$/ && index($0, "EASYTIER_DNS") { print $1 }' | sort -rn)
for n in $nums; do $IT -t nat -D OUTPUT "$n" 2>/dev/null; done
$IT -t nat -F EASYTIER_DNS 2>/dev/null
$IT -t nat -X EASYTIER_DNS 2>/dev/null

# 清除本模块配套的魔法 DNS 看门狗（/data/adb/service.d 不属于模块目录，需手动删）
rm -f /data/adb/service.d/99-easytier-dns-watchdog.sh

rm -rf $MODDIR/*
rm -rf /data/adb/easytier-magisk
