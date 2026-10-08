# Snell v6 Docker 双栈双出口部署

本项目基于 **Surge 官方 Snell v6 二进制文件** 自建 Docker 镜像，无需任何第三方镜像，通过运行两个独立实例，分别提供强制 IPv4 出口和强制 IPv6 出口的代理服务。

## 项目架构

部署后会运行两个 Docker 容器：

| 容器名称 | 监听端口 | DNS 出口偏好 | 用途 |
| :--- | :--- | :--- | :--- |
| `snell-v4-exit` | 6666 | ipv4-only | 目标网站只看到 IPv4 出口 |
| `snell-v6-exit` | 8888 | ipv6-only | 目标网站只看到 IPv6 出口 |

两个容器共享同一个密码（PSK）和协议模式（mode），均使用 `network_mode: host` 直接绑定宿主机网络，确保 IPv4 和 IPv6 流量都能正常进出。

## 文件结构

- `Dockerfile`：用于构建基于 Debian slim 和官方 Snell 二进制的镜像。
- `docker-compose.yml`：定义两个 Snell 容器的启动逻辑和挂载配置。
- `install.sh`：一键部署脚本，自动下载官方最新二进制、构建镜像、生成配置、放行防火墙并启动容器。
- `README.md`：项目说明文档。
- `.dockerignore` / `.gitignore`：构建和 Git 上传时的忽略规则，防止把大体积二进制文件传到仓库。

## 部署要求

- 服务器系统：Debian 13（或其他基于 Debian 的系统）。
- 已安装 Docker 和 Docker Compose 插件。
- 服务器已分配公网 IPv4 和 IPv6 地址。

## 一键部署

```bash
SNELL_PSK='你的密码' bash <(curl -fsSL https://raw.githubusercontent.com/linyu-yuan/snell/main/install.sh)
```

部署完成后，需前往 DMIT 网页控制台的安全组，放行 `6666` 和 `8888` 的 TCP+UDP 入站流量。

## 以后修改密码或端口

不要修改 GitHub 上的代码。直接编辑服务器上的配置文件：

```bash
nano /root/snell-config-v4/snell-server.conf
nano /root/snell-config-v6/snell-server.conf
```

修改 `psk` 或 `listen` 中的端口，保存后执行：

```bash
cd /root && docker compose up -d
```

## Surge 客户端配置

在 `[Proxy]` 段落中加入：

```ini
[Proxy]
Snell-v4-exit = snell, 你的服务器IP, 6666, psk=你的密码, version=6, reuse=true, mode=unshaped
Snell-v6-exit = snell, 你的服务器IP, 8888, psk=你的密码, version=6, reuse=true, mode=unshaped
```

同时在 `[General]` 中确保开启 IPv6 支持：

```ini
ipv6 = true
```

## 注意事项

- **官方二进制**：本项目只使用 Surge 官方发布的 Snell v6 二进制，不依赖任何第三方维护的镜像。
- **模式必须一致**：服务端和客户端 `mode` 必须都是 `unshaped`，否则无法连接。
- **Snell v6 不支持 obfs**：无需配置混淆参数。
- **纯 IPv6 出口节点**：监听地址为 `[::]:8888`，专为 IPv6 出口环境优化。