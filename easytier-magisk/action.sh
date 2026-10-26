#!/data/adb/magisk/busybox sh
#
# 管理器里的「操作」按钮（KernelSU / Magisk 的 action.sh 接口）：重启 easytier 服务
#
MODDIR=${0%/*}
IPTABLES=/system/bin/iptables

if [ -f "$MODDIR/disable" ]; then
    echo "模块已禁用（存在 $MODDIR/disable），不重启"
    exit 0
fi

# 先干掉旧实例（run.sh 退出时会自己撤掉 DNS 规则），否则旧的后台守护会和新实例抢规则
pkill -f "$MODDIR/run.sh" 2>/dev/null
sleep 1
pkill -f "$MODDIR/easytier/" 2>/dev/null
sleep 1

setsid sh "$MODDIR/run.sh" >/dev/null 2>&1 &
sleep 3

echo "=== easytier-core ==="
pgrep -af "$MODDIR/easytier/" || echo "(未启动)"
echo "=== DNS 劫持规则（只应命中 *.et.net）==="
$IPTABLES -t nat -S OUTPUT | grep 100.100.100.101 || echo "(没有规则)"
echo "=== log/start.log（最后 30 行）==="
tail -n 30 "$MODDIR/log/start.log"
