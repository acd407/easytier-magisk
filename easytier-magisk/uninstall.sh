MODDIR=${0%/*}

# 清理魔法 DNS 重定向规则，避免残留规则把 App 的 DNS 指向已经不存在的魔法 DNS
/system/bin/iptables -t nat -D OUTPUT -p udp --dport 53 -j EASYTIER_DNS 2>/dev/null
/system/bin/iptables -t nat -F EASYTIER_DNS 2>/dev/null
/system/bin/iptables -t nat -X EASYTIER_DNS 2>/dev/null

rm -rf $MODDIR/*
rm -rf /data/adb/easytier-magisk
