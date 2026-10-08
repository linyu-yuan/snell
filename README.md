# Snell v6 Docker 单实例双栈入口部署

本项目基于 Surge 官方 Snell v6 二进制文件自建 Docker 镜像，无需任何第三方镜像。
采用单实例方案，通过 `network_mode: host` 直接绑定宿主机，同时监听 IPv4 和 IPv6 入口。

## 项目架构

- 运行 1 个 Docker 容器（`snell`），监听端口 `6666`。
- 只需一套配置文件，IPv4 和 IPv6 客户端（Surge 节点）均可连入。
- 目标网站出口协议由服务器自身决定，不在服务端强制指定。

## 文件结构

- `Dockerfile`：基于 Debian slim 和官方 Snell 二进制构建镜像。
- `docker-compose.yml`：定义 Snell 容器的启动逻辑和挂载配置。
- `install.sh`：一键部署脚本，自动下载官方最新二进制、构建镜像、生成配置、放行防火墙并启动容器。
- `README.md`：项目说明文档。
- `.dockerignore` / `.gitignore`：构建和 Git 上传时的忽略规则。

## 一键部署

```bash
SNELL_PSK='你的密码' bash <(curl -fsSL https://raw.githubusercontent.com/linyu-yuan/snell/main/install.sh)
```

部署完成后，需前往 DMIT 网页控制台的安全组，放行 `6666` 的 TCP+UDP 入站流量。

## 以后修改密码或端口

直接在服务器上执行以下命令修改密码（会提示你输入新密码）：

```bash
read -p "请输入新密码: " NEW_PSK && sed -i "s|^psk = .*|psk = ${NEW_PSK}|" /root/snell-config/snell-server.conf && cd /root && docker compose up -d && echo ">>> 密码已修改并重启！"
```

**注意**：修改完成后，需同步修改 Surge 客户端里两个节点的密码。

## Surge 客户端配置

在 `[Proxy]` 段落中加入两个节点（一个填 v4 地址，一个填 v6 地址，端口都是 6666）：

```ini
[Proxy]
Snell-v4-Entry = snell, 你的服务器IPv4地址, 6666, psk=你的密码, version=6, reuse=true, mode=unshaped
Snell-v6-Entry = snell, 你的服务器IPv6地址, 6666, psk=你的密码, version=6, reuse=true, mode=unshaped
```

同时在 `[General]` 中确保开启 IPv6 支持：

```ini
ipv6 = true
```

## 注意事项

- **官方二进制**：本项目只使用 Surge 官方发布的 Snell v6 二进制，不依赖任何第三方维护的镜像。
- **模式必须一致**：服务端和客户端 `mode` 必须都是 `unshaped`，否则无法连接。
- **Snell v6 不支持 obfs**：无需配置混淆参数。