#!/usr/bin/env bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$WORKDIR"

if [[ ! -f docker-compose.yml ]]; then
  echo ">>> 未找到 docker-compose.yml，请先运行 install.sh"
  exit 1
fi

# ---------- 检查 PSK 是否还是占位符 ----------
if grep -q '123456789012' docker-compose.yml; then
  echo ">>> 错误: docker-compose.yml 中密码仍然是占位符 123456789012"
  echo ">>> 请先修改两处 PSK，然后再运行 apply.sh"
  exit 1
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
echo "apply.sh 执行完成"
echo "=============================================="
echo "Surge 配置参考（手动填入服务器 IP 和密码）："
echo ""
N=1
for PORT in $PORTS; do
  echo "Snell-${N} = snell, 你的服务器IP, ${PORT}, psk=你的密码, version=6, reuse=true, mode=unshaped"
  N=$((N+1))
done
echo ""
echo "同时确保 Surge [General] 中设置 ipv6 = true"
echo "并确认 DMIT 网页安全组已放行以上端口的 TCP+UDP"
echo "=============================================="