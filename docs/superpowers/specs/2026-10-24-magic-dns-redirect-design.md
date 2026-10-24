# 安卓魔法 DNS 重定向设计

## 目标

让安卓上的 App 在 `accept_dns = true` 时能解析 `xxx.et.net`（魔法 DNS），且不影响 EasyTier 自身向上游解析、不在 EasyTier 停止后残留失效规则。

## 背景

- 安卓的域名解析由 `netd` 内的 stub resolver 代 App 完成，按 App 所在网络的 netId 使用该网络的 DNS 配置，**不读 `/etc/resolv.conf`**；模块此前注入的 resolv.conf 只对 EasyTier(hickory) 自己生效。
- 现代安卓无法从 root shell 侧可靠地修改 netd 的 DNS 配置：`ndc resolver setifdns` 在 Android 5 起被 `setnetdns <netId>` 取代，Android 10 起 resolver 拆到 `com.android.resolv` APEX，只提供受权限约束的 binder 接口；且 DNS 配置的真实来源是 ConnectivityService，网络事件会覆盖直写的值。
- EasyTier 的 tun（`easytier-core` 直接打开 `/dev/net/tun`）没有注册 netId，App 的解析也不会走它，因此"给 tun 设 DNS"这条路径不成立。
- 实测本机（ColorOS/Android 13 类 ROM）：`accept_dns = true` 时 EasyTier 会加 `100.100.100.101 dev tun0 proto static metric 65535` 路由，魔法 DNS 只监听 UDP/53（TCP/53 连不上），且对非 `et.net` 域名会转发到系统上游。

## 方案

在 `net` 层用一条 nat 规则改写 **netd 代发的 DNS 查询**，不改 netd 配置：

```
iptables -t nat -N EASYTIER_DNS
iptables -t nat -A OUTPUT -p udp --dport 53 -j EASYTIER_DNS
iptables -t nat -A EASYTIER_DNS -p udp -m mark ! --mark 0x0/0xffffffff -j DNAT --to-destination 100.100.100.101:53
```

关键点：

- **用 fwmark 区分来源**。netd 的 DNS socket 会按 App 所在网络打 netId fwmark，EasyTier 自己的解析 socket 不带 fwmark。实测：`ping`（走 netd）产生的查询全部带 mark，经魔法 DNS 触发的上游查询全部 mark 为 0。因此只改写带 mark 的查询，EasyTier 的上游查询直连，不会自环。
- **只在路由就绪时启用**。`ip route show 100.100.100.101` 有输出才填规则，否则清空链，避免 `accept_dns` 未启用时把 App 的 DNS 打到不可达地址。
- **生命周期跟随 EasyTier**。`run.sh` 每 5 秒巡检一次路由：路由消失或存在 `/data/adb/easytier-magisk/dns_redirect_off` 时清空链；`run.sh` 退出、`disable` 触发、`uninstall.sh` 执行时移除跳转规则并删除自定义链。
- **不动 TCP/53 与 IPv6**。该版本魔法 DNS 只支持 UDP/IPv4，改写 TCP 会打断截断响应重传，IPv6 无法 DNAT 到 IPv4。

## 验证

在本机实测（临时规则，验证后清理）：

- `iptables -t nat -S` 规则幂等：重复 apply 不产生重复规则；pause 只清空链、remove 清空并删除链。
- 应用规则后 `ping ace5.et.net` / `redrix.et.net` 经系统解析器解析到虚拟网地址（10.144.144.3 / 10.144.144.2）。
- 应用规则后 `ping www.qq.com`、`www.aliyun.com` 仍正常解析，说明魔法 DNS 的上游转发未被改写（无自环）。
- `dumpsys dnsresolver` 中 netd 的 DNS 服务器配置保持不变，确认改写发生在 net 层。
- 期间 `easytier-core` CPU 占用 0.0%，peer 列表正常。

## 限制

- 只覆盖走系统解析器的 App；App 自带 DNS 客户端、走明文 53 且不打 mark 的查询不受影响。
- 用户开启私人 DNS（DoT）时查询走 853，不经过该规则。
- IPv6-only DNS 网络（部分蜂窝网络）下 `xxx.et.net` 不可解析。
- 若同时运行其它依赖自身 DNS 的代理/VPN，其查询也会被改写；提供 `dns_redirect_off` 开关关闭。
- `et.net` 是真实注册的公共域名（实测关闭重定向时 `ace5.et.net` 解析到 13.248.169.48），切换开关后 netd 会缓存旧答案直到 TTL 过期；建议用 `--tld-dns-zone` 换成自用后缀。
