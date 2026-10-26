#!/data/adb/magisk/busybox sh
#
# EasyTier for Magisk 启动脚本
#   1) 在私有 mount ns 里给 easytier 造一个 /etc/resolv.conf（不影响系统）
#   2) 只劫持 *.et.net 的 DNS 查询到魔法 DNS，其它 DNS 一律不碰
#   3) 前台跑 easytier-core，日志写 log/start.log
#
MODDIR=${0%/*}
DATADIR=/data/adb/easytier-magisk
BB=/data/adb/magisk/busybox
IPTABLES=/system/bin/iptables
MAGIC_DNS=100.100.100.101

# DNS 线上格式里 QNAME 末尾的 ".et.net" 固定是 02 'e' 't' 03 'n' 'e' 't' 00，
# 用 -m string 做字节串匹配（等价于任意偏移匹配，--icase 只支持 bm 算法）
ET_HEX="|026574036e657400|"

case "$(getprop ro.product.cpu.abi)" in
    armeabi-v7a) ARCH=arm ;;
    arm64-v8a)   ARCH=arm64 ;;
    x86)         ARCH=x86 ;;
    x86_64)      ARCH=x64 ;;
    *)           ARCH=unknown ;;
esac

mkdir -p "$MODDIR/log" "$DATADIR/ovl"

# ---------------------------------------------------------------------------
# 魔法 DNS 劫持：一条规则搞定
#   -p udp --dport 53       只碰 DNS-over-UDP
#   -m mark ! --mark 0x0    只碰 netd 代 App 发的查询；easytier 自己 mark=0，不自环
#   -m string ... .et.net   只碰 QNAME 以 .et.net 结尾的查询
# ---------------------------------------------------------------------------
dns() {
    $IPTABLES -t nat "$@" -p udp --dport 53 -m mark ! --mark 0x0 \
        -m string --algo bm --icase --hex-string "$ET_HEX" \
        -j DNAT --to-destination "$MAGIC_DNS":53
}
dns_on()  { dns -C OUTPUT 2>/dev/null || dns -A OUTPUT; }
dns_off() { while dns -C OUTPUT 2>/dev/null; do dns -D OUTPUT; done; }

# 清掉旧版本留下的 EASYTIER_DNS 自定义链（一次性，之后不再用链）
if $IPTABLES -t nat -L EASYTIER_DNS >/dev/null 2>&1; then
    for n in $($IPTABLES -t nat -L OUTPUT --line-numbers -n |
            awk '$1 ~ /^[0-9]+$/ && /EASYTIER_DNS/ { print $1 }' | sort -rn); do
        $IPTABLES -t nat -D OUTPUT "$n"
    done
    $IPTABLES -t nat -F EASYTIER_DNS
    $IPTABLES -t nat -X EASYTIER_DNS
fi

dns_on
trap dns_off EXIT INT TERM HUP

# 后台守护：每 5s 把规则补回来（有的 ROM 会重置 iptables）；
# 出现 disable 就退出并杀掉 easytier，出现 dns_redirect_off 就撤掉劫持
(
    while [ ! -f "$MODDIR/disable" ]; do
        if [ -f "$DATADIR/dns_redirect_off" ]; then dns_off; else dns_on; fi
        sleep 5
    done
    dns_off
    pkill -f "$MODDIR/easytier/$ARCH/easytier-core"
) &
WATCHER=$!

# ---------------------------------------------------------------------------
# easytier 转发用的上游 DNS：hickory 只认 /etc/resolv.conf，Android 上没有这个
# 文件，所以在私有 mount ns 里用 overlayfs 给 /system/etc 盖一层（不动系统别的进程）
# ---------------------------------------------------------------------------
$BB cat > "$DATADIR/resolv.conf" <<EOF
nameserver 114.114.114.114
nameserver 223.5.5.5
nameserver 119.29.29.29
nameserver 8.8.8.8
EOF

/system/bin/unshare -m $BB sh -c "
    $BB mount --make-rprivate / 2>/dev/null
    $BB mount -t tmpfs tmpfs '$DATADIR/ovl' 2>/dev/null
    $BB mkdir -p '$DATADIR/ovl/upper' '$DATADIR/ovl/work'
    $BB cp '$DATADIR/resolv.conf' '$DATADIR/ovl/upper/resolv.conf'
    $BB mount -t overlay overlay \
        -o lowerdir=/system/etc,upperdir='$DATADIR/ovl/upper',workdir='$DATADIR/ovl/work' /system/etc
    exec '$MODDIR/easytier/$ARCH/easytier-core' -c '$DATADIR/config.toml'
" > "$MODDIR/log/start.log" 2>&1

kill $WATCHER 2>/dev/null
dns_off
