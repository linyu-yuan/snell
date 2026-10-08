#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="snell-v6:official"
FALLBACK_VER="v6.0.0rc2"
SNELL_ARCH="amd64"
DEFAULT_PORT_V4=66666
DEFAULT_PORT_V6=88888
# 密码从环境变量获取，没传时用占位符 123456789012
SNELL_PSK="${SNELL_PSK:-123456789012}"

WORKDIR="$(pwd)"
cd "$WORKDIR"

# ---------- 检查依赖 ----------
for cmd in wget unzip docker curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo ">>> 缺少 $cmd，请先安装后再运行脚本。"
    exit 1
  fi
done

if ! docker version >/dev/null 2>&1; then
  echo ">>> Docker 未运行或不可用，请检查。"
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo ">>> docker compose 不可用，请检查。"
  exit 1
fi

# ---------- 获取最新版本 ----------
RELEASE_PAGE="https://kb.nssurge.com/surge-knowledge-base/release-notes/snell"
echo ">>> 正在获取 Snell 最新版本..."
LATEST_VER=$(curl -fsSL "$RELEASE_PAGE" 2>/dev/null | grep -oE 'snell-server-v[0-9]+\.[0-9]+\.[0-9]+[a-z0-9]*-linux-amd64\.zip' | sed 's/snell-server-\(v[0-9.]*[a-z0-9]*\)-linux-amd64\.zip/\1/' | sort -V | tail -n1 || true)
if [[ -z "$LATEST_VER" ]]; then
  echo ">>> 解析失败，回退到 ${FALLBACK_VER}"
  SNELL_VER="$FALLBACK_VER"
else
  SNELL_VER="$LATEST_VER"
  echo ">>> 使用版本: $SNELL_VER"
fi

# ---------- 下载二进制 ----------
rm -f snell-server snell-server.zip
echo ">>> 下载 Snell ${SNELL_VER} (${SNELL_ARCH}) ..."
wget -q "https://dl.nssurge.com/snell/snell-server-${SNELL_VER}-linux-${SNELL_ARCH}.zip" -O snell-server.zip
unzip -o snell-server.zip
rm -f snell-server.zip
chmod +x snell-server

# ---------- 确保 Dockerfile 存在 ----------
if [[ ! -f Dockerfile ]]; then
  echo ">>> 本地没有 Dockerfile，从 GitHub 下载..."
  curl -fsSL https://raw.githubusercontent.com/linyu-yuan/snell/main/Dockerfile -o Dockerfile
fi

# ---------- 构建镜像 ----------
echo ">>> 构建镜像 ${IMAGE_NAME} ..."
docker build -t "${IMAGE_NAME}" .

# ---------- 生成 docker-compose.yml（不覆盖已有） ----------
if [[ ! -f docker-compose.yml ]]; then
  # 注意：这里用双引号 YAML 而不是单引号，才能让变量生效
  cat > docker-compose.yml <<YAML
services:
  snell-v4-exit:
    image: snell-v6:official
    container_name: snell-v4-exit
    restart: always
    network_mode: host
    logging:
      driver: json-file
      options:
        max-size: "5m"
        max-file: "2"
    command:
      - "-p"
      - "${DEFAULT_PORT_V4}"
      - "-psk"
      - "${SNELL_PSK}"
      - "-mode"
      - "unshaped"
      - "-listen"
      - "0.0.0.0,[::]"
      - "-dns-ip-preference"
      - "ipv4-only"

  snell-v6-exit:
    image: snell-v6:official
    container_name: snell-v6-exit
    restart: always
    network_mode: host
    logging:
      driver: json-file
      options:
        max-size: "5m"
        max-file: "2"
    command:
      - "-p"
      - "${DEFAULT_PORT_V6}"
      - "-psk"
      - "${SNELL_PSK}"
      - "-mode"
      - "unshaped"
      - "-listen"
      - "0.0.0.0,[::]"
      - "-dns-ip-preference"
      - "ipv6-only"
YAML
  echo ">>> 已生成 docker-compose.yml"
else
  echo ">>> docker-compose.yml 已存在，不覆盖"
fi

# ---------- 从 docker-compose.yml 提取端口 ----------
PORTS=$(grep -A1 '"-p"' docker-compose.yml | grep -oE '"[0-9]+"' | tr -d '"' | sort -u)

if [[ -z "$PORTS" ]]; then
  echo ">>> 未能从 docker-compose.yml 中提取端口，请检查文件格式。"
  exit 1
fi
echo ">>> 检测到端口: $(echo $PORTS | tr '\n' ' ')"

# ---------- 确保 iptables-persistent 已安装 ----------
if ! command -v netfilter-persistent >/dev/null 2>&1; then
  echo ">>> 安装 iptables-persistent ..."
  export DEBIAN_FRONTEND=noninteractive
  echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections 2>/dev/null || true
  echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections 2>/dev/null || true
  apt-get update -qq
  apt-get install -y -qq iptables-persistent >/dev/null 2>&1 || true
fi

# ---------- 停止旧容器后检查端口占用 ----------
echo ">>> 停止旧容器..."
docker compose down 2>/dev/null || true

for PORT in $PORTS; do
  if ss -tlnup 2>/dev/null | grep -qE ":${PORT}[[:space:]]"; then
    echo ">>> 错误: 端口 ${PORT} 已被其他进程占用"
    ss -tlnup | grep -E ":${PORT}[[:space:]]"
    exit 1
  fi
done

# ---------- 清理旧的 snell 防火墙规则 ----------
echo ">>> 清理旧的 snell 防火墙规则..."
iptables -S INPUT 2>/dev/null | grep 'snell' | sed 's/^-A/iptables -D/' | bash 2>/dev/null || true
ip6tables -S INPUT 2>/dev/null | grep 'snell' | sed 's/^-A/ip6tables -D/' | bash 2>/dev/null || true

# ---------- 添加新的防火墙规则 ----------
echo ">>> 添加新的防火墙规则..."
for PORT in $PORTS; do
  iptables -A INPUT -p tcp --dport "${PORT}" -m comment --comment "snell" -j ACCEPT
  iptables -A INPUT -p udp --dport "${PORT}" -m comment --comment "snell" -j ACCEPT
  ip6tables -A INPUT -p tcp --dport "${PORT}" -m comment --comment "snell" -j ACCEPT
  ip6tables -A INPUT -p udp --dport "${PORT}" -m comment --comment "snell" -j ACCEPT
done

# ---------- 持久化防火墙规则 ----------
echo ">>> 保存防火墙规则..."
netfilter-persistent save 2>/dev/null || true
systemctl enable netfilter-persistent 2>/dev/null || true

# ---------- 启动容器 ----------
echo ">>> 启动 Snell 容器..."
docker compose up -d

# ---------- 验证监听（TCP + UDP） ----------
echo ""
echo ">>> 监听状态 (TCP + UDP):"
for PORT in $PORTS; do
  if ss -tlnup 2>/dev/null | grep -qE ":${PORT}[[:space:]]"; then
    ss -tlnup | grep -E ":${PORT}[[:space:]]"
  else
    echo "  (端口 ${PORT} 未监听)"
  fi
done

echo ""
echo "=============================================="
echo "部署完成！"
echo "=============================================="
echo "当前使用的密码: ${SNELL_PSK}"
echo ""
echo "Surge 配置参考（手动填入服务器 IP 和密码）："
echo ""
N=1
for PORT in $PORTS; do
  echo "Snell-${N} = snell, 你的服务器IP, ${PORT}, psk=${SNELL_PSK}, version=6, reuse=true, mode=unshaped"
  N=$((N+1))
done
echo ""
echo "请确保 Surge [General] 中设置 ipv6 = true"
echo "并确认 DMIT 网页安全组已放行以上端口的 TCP+UDP"
echo "=============================================="