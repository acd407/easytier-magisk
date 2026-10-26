# easytier-magisk
[EasyTier](https://github.com/EasyTier/EasyTier) for Magisk

- 安装目录：`/data/adb/modules/easytier-magisk`
- 配置文件：`/data/adb/easytier-magisk/config.toml`

修改配置文件后，点击magisk app中的`操作`按钮重新启动

点击magisk app中的开关，停止运行easytier

## 魔法 DNS（`accept_dns`）

在 `config.toml` 的 `[flags]` 中设置 `accept_dns = true` 后，EasyTier 会把 `100.100.100.101`
作为魔法 DNS（可用 `主机名.et.net` 访问虚拟网内其它节点）。

安卓上的域名解析由 `netd` 代 App 完成，只认 netd 里的网络 DNS 配置，不读 `/etc/resolv.conf`，
所以模块额外把 **带 netId fwmark 且 QNAME 以 `.et.net` 结尾的 UDP/53 查询**（即 netd 代 App
发出的查询）DNAT 到 `100.100.100.101`，让 App 也能解析 `xxx.et.net`。EasyTier 自身向上游解析的
查询不带 fwmark，不会被改写，因此不会自环；其它域名（非 `.et.net`）的查询完全不受影响。

劫持只有一条 nat/OUTPUT 规则，`run.sh` 启动时安装、退出时撤销，运行期间后台守护每 5 秒
补一次规则（部分 ROM 会重置 iptables）。

限制：

- 魔法 DNS 目前只有 UDP，故不改写 TCP/53；IPv6 无法 DNAT 到 IPv4，IPv6-only 网络（部分蜂窝网络）不生效
- 规则在 `run.sh` 运行期间一直存在，不检查魔法 DNS 路由是否就绪：`accept_dns = false` 时
  `xxx.et.net` 会解析失败（不会回落到公网地址）
- 如果你不需要 App 解析 `xxx.et.net`，创建空文件 `/data/adb/easytier-magisk/dns_redirect_off`
  关闭该功能（5 秒内生效）
- `et.net` 是真实注册的公共域名：关闭重定向时会解析到公网地址，且 netd 会缓存该结果直到 TTL 过期。
  如需避免冲突，可用 `--tld-dns-zone` 换成自用后缀（如 `et.internal`）
