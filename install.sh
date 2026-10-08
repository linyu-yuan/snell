#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="snell-v6:official"
FALLBACK_VER="v6.0.0rc2"
SNELL_ARCH="amd64"
DEFAULT_PORT_V4=66666
DEFAULT_PORT_V6=88888
WORKDIR="$(pwd)"
cd "$WORKDIR"

# ---------- 检查依赖 ----------
for cmd in wget unzip docker curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo ">>> 缺少 $cmd，请先安装后再运行脚本。"
    exit 1
  fi
done

# ---------- 检查 Docker 和 Compose ----------
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

# ---------- 强制重新下载官方二进制 ----------
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
      - "123456789012"
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
      - "123456789012"
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

# ---------- 完成提示 ----------
echo ""
echo "=============================================="
echo "准备工作已完成！"
echo "=============================================="
echo "请执行以下步骤："
echo "1. 编辑 docker-compose.yml，把两处 PSK 从 123456789012 改为你的真实密码"
echo "2. 执行: bash apply.sh"
echo "3. 在 DMIT 网页控制台的安全组中放行端口 ${DEFAULT_PORT_V4} 和 ${DEFAULT_PORT_V6} 的 TCP+UDP"
echo ""
echo "注意：当前密码仍是占位符 123456789012，请务必修改后再启动！"
echo "=============================================="