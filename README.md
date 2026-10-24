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
所以模块额外把 **带 netId fwmark 的 UDP/53 查询**（即 netd 代 App 发出的查询）DNAT 到
`100.100.100.101`，让 App 也能解析 `xxx.et.net`。EasyTier 自身向上游解析的查询不带 fwmark，
不会被改写，因此不会自环。

限制：

- 魔法 DNS 目前只有 UDP，故不改写 TCP/53；IPv6 无法 DNAT 到 IPv4，IPv6-only 网络（部分蜂窝网络）不生效
- 只在魔法 DNS 路由存在时生效（即 `accept_dns = true` 且 easytier 已启动），easytier 停止后自动撤销
- 会改写所有走系统解析器的 DNS 查询；如果手机同时运行其它依赖自身 DNS 的代理/VPN，
  或你不需要 App 解析 `xxx.et.net`，创建空文件 `/data/adb/easytier-magisk/dns_redirect_off` 关闭该功能（5 秒内生效）
- `et.net` 是真实注册的公共域名：关闭重定向时会解析到公网地址，且 netd 会缓存该结果直到 TTL 过期。
  如需避免冲突，可用 `--tld-dns-zone` 换成自用后缀（如 `et.internal`）
