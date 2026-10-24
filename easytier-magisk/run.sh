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
DATADIR=/data/adb/easytier-magisk
DNS_CONF=$DATADIR/resolv.conf
OVL=$DATADIR/ovl

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

kill $check_disable_pid
