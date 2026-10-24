#!/data/adb/magisk/busybox sh

MODDIR=${0%/*}

# 从系统属性获取 CPU ABI
ARCH=$(getprop ro.product.cpu.abi)

case "$ARCH" in
    armeabi-v7a) ARCH="arm" ;;
    arm64-v8a)   ARCH="arm64" ;;
    x86)         ARCH="x86" ;;
    x86_64)      ARCH="x64" ;;
    *)           ARCH="unknown" ;;
esac

BB=/data/adb/magisk/busybox
UNSHARE=/system/bin/unshare
IP=/system/bin/ip
IPTABLES=/system/bin/iptables
DATADIR=/data/adb/easytier-magisk
DNS_CONF=$DATADIR/resolv.conf
OVL=$DATADIR/ovl

# 魔法 DNS 地址：accept_dns = true 时 easytier 会把该地址的路由加到 tun0
MAGIC_DNS_IP=100.100.100.101
DNS_REDIRECT_CHAIN=EASYTIER_DNS

mkdir -p $MODDIR/log

# EasyTier(hickory) 只认 /etc/resolv.conf，Android 系统里通常没有该文件。
# 模块不再附带 system/etc/resolv.conf（避免全局改写系统 DNS，且 KernelSU
# 未装 metamodule 时该文件不会被挂载），改在 easytier 的私有挂载命名空间里
# 用 overlayfs 生成该文件，不影响系统其它进程。
$BB cat > $DNS_CONF <<EOF
nameserver 114.114.114.114
nameserver 223.5.5.5
nameserver 119.29.29.29
nameserver 8.8.8.8
EOF

# App 侧 DNS 重定向（魔法 DNS）
#
# 现代 Android 的域名解析由 netd 代 App 完成，只认 netd 里的网络 DNS 配置，
# 不读 /etc/resolv.conf，所以上面的 resolv.conf 只对 easytier 自己生效。
# 这里把带 fwmark 的 UDP/53 查询（netd 代 App 发出的查询）DNAT 到魔法 DNS：
#   - netd 的 DNS socket 按 netId 打 fwmark，App 走系统解析器的查询都会被改写；
#   - easytier 自己向上游解析的查询 fwmark 为 0，不会被改写，避免自环。
# 只在魔法 DNS 路由存在时生效（即 accept_dns = true），否则清空规则。
# 兼容性：魔法 DNS 只有 UDP，故不改写 TCP/53；IPv6 无法 DNAT 到 IPv4，未处理。
dns_redirect_disabled() {
    [ -f "$DATADIR/dns_redirect_off" ]
}

dns_redirect_apply() {
    $IP route show "$MAGIC_DNS_IP" 2>/dev/null | grep -q . || return 1

    $IPTABLES -t nat -n -L "$DNS_REDIRECT_CHAIN" >/dev/null 2>&1 ||
        $IPTABLES -t nat -N "$DNS_REDIRECT_CHAIN" 2>/dev/null

    $IPTABLES -t nat -C OUTPUT -p udp --dport 53 -j "$DNS_REDIRECT_CHAIN" >/dev/null 2>&1 ||
        $IPTABLES -t nat -A OUTPUT -p udp --dport 53 -j "$DNS_REDIRECT_CHAIN" 2>/dev/null

    $IPTABLES -t nat -C "$DNS_REDIRECT_CHAIN" -p udp -m mark ! --mark 0x0/0xffffffff \
        -j DNAT --to-destination "$MAGIC_DNS_IP":53 >/dev/null 2>&1 ||
        $IPTABLES -t nat -A "$DNS_REDIRECT_CHAIN" -p udp -m mark ! --mark 0x0/0xffffffff \
            -j DNAT --to-destination "$MAGIC_DNS_IP":53 2>/dev/null

    return 0
}

dns_redirect_pause() {
    $IPTABLES -t nat -F "$DNS_REDIRECT_CHAIN" 2>/dev/null
}

dns_redirect_remove() {
    $IPTABLES -t nat -D OUTPUT -p udp --dport 53 -j "$DNS_REDIRECT_CHAIN" 2>/dev/null
    $IPTABLES -t nat -F "$DNS_REDIRECT_CHAIN" 2>/dev/null
    $IPTABLES -t nat -X "$DNS_REDIRECT_CHAIN" 2>/dev/null
}

check_magic_dns() {
    while [ ! -f "$MODDIR/disable" ]; do
        if dns_redirect_disabled || ! dns_redirect_apply; then
            dns_redirect_pause
        fi
        sleep 5
    done
    dns_redirect_remove
}

cleanup() {
    dns_redirect_remove
}

trap cleanup EXIT INT TERM HUP

check_disable() {

    while [ ! -f $MODDIR/disable ]; do
        sleep 2
    done

    PIDS=$(pgrep -f "$MODDIR/easytier/$ARCH/easytier-core")
    kill -9 $PIDS
    echo "Easytier $PIDS 服务停止" >> $MODDIR/log/start.log
}

check_disable &
check_disable_pid=$!

check_magic_dns &
check_magic_dns_pid=$!

BB="$BB" UNSHARE="$UNSHARE" DATADIR="$DATADIR" DNS_CONF="$DNS_CONF" OVL="$OVL" \
MODDIR="$MODDIR" ARCH="$ARCH" \
$UNSHARE -m $BB sh -c '
    "$BB" mount --make-rprivate / 2>/dev/null
    "$BB" mkdir -p "$OVL"
    "$BB" mount -t tmpfs tmpfs "$OVL" 2>/dev/null
    "$BB" mkdir -p "$OVL/upper" "$OVL/work"
    "$BB" cp "$DNS_CONF" "$OVL/upper/resolv.conf" 2>/dev/null
    "$BB" mount -t overlay overlay -o "lowerdir=/system/etc,upperdir=$OVL/upper,workdir=$OVL/work" /system/etc 2>/dev/null
    exec "$MODDIR/easytier/$ARCH/easytier-core" -c "$DATADIR/config.toml"
' > $MODDIR/log/start.log 2>&1

kill $check_disable_pid $check_magic_dns_pid 2>/dev/null
wait 2>/dev/null
dns_redirect_remove
