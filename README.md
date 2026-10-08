# Snell v6 Docker 部署

基于 Surge 官方 Snell v6 二进制自建 Docker 镜像，跑两个实例，分别强制 IPv4 出口和 IPv6 出口。

## 一键部署

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/linyu-yuan/snell/main/install.sh)
```

## 首次部署

1. 运行 `install.sh`，它会下载官方最新 Snell v6 二进制、构建镜像、生成 `docker-compose.yml`。
2. 编辑 `docker-compose.yml`，把两处 PSK 占位符 `123456789012` 改成你的真实密码。
3. 运行 `bash apply.sh`，自动更新防火墙规则并启动容器。
4. 在 DMIT 网页控制台安全组放行端口 `66666` 和 `88888` 的 TCP+UDP。

## 以后改端口或密码

1. 编辑 `docker-compose.yml`，修改 `-p` 下面的端口值或 PSK。
2. 运行 `bash apply.sh`。
3. 在 DMIT 网页控制台安全组放行新端口。

`apply.sh` 会自动：

- 检查密码是否还是占位符
- 从 `docker-compose.yml` 读取端口
- 检查端口是否被占用
- 更新 iptables/ip6tables 规则并持久化
- 重启容器
- 验证 TCP + UDP 监听状态

## Surge 客户端配置

两个节点分别指向两个端口，分别强制 IPv4 出口和 IPv6 出口：

```ini
[Proxy]
Snell-v4-exit = snell, 你的服务器IP, 66666, psk=你的密码, version=6, reuse=true, mode=unshaped
Snell-v6-exit = snell, 你的服务器IP, 88888, psk=你的密码, version=6, reuse=true, mode=unshaped
```

同时在 `[General]` 中确保：

```ini
ipv6 = true
```

## 说明

- 使用 Surge 官方 Snell v6 二进制，不依赖第三方镜像。
- `snell-v4-exit`（端口 66666）：`-dns-ip-preference ipv4-only`，目标网站只看到 IPv4 出口。
- `snell-v6-exit`（端口 88888）：`-dns-ip-preference ipv6-only`，目标网站只看到 IPv6 出口。
- `network_mode: host` 确保双栈监听直接绑定宿主机。
- 防火墙规则由 `apply.sh` 自动更新并持久化，重启后仍生效。
- Snell v6 不支持 obfs 混淆。
- `mode` 客户端必须与服务端一致（`unshaped`）。