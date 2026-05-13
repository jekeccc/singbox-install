#!/bin/bash
# =============================================
# sing-box Hysteria2 一键安装脚本（最终完整版）
# 支持端口跳跃 + 客户端二维码 + 管理菜单
# =============================================

set -e

# ================== 可自定义参数 ==================
DOMAIN=""                          # 留空 = 使用IP；填域名 = 自动申请证书
EMAIL="admin@example.com"
HY2_PASSWORD=$(openssl rand -hex 16)
HY2_PORT=443
HOP_PORT_START=20000
HOP_PORT_END=30000
MASQUERADE="https://www.bing.com"
# ================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print() { echo -e "$1"; }

check_root() {
    [ "$(id -u)" -ne 0 ] && { print "${RED}请使用 root 用户运行此脚本！${NC}"; exit 1; }
}

interactive_settings() {
    print "${GREEN}=== 端口跳跃设置（直接回车使用默认值）===${NC}"
    read -p "主端口 [443]: " p; [ -n "$p" ] && HY2_PORT=$p
    read -p "跳跃起始端口 [20000]: " s; [ -n "$s" ] && HOP_PORT_START=$s
    read -p "跳跃结束端口 [30000]: " e; [ -n "$e" ] && HOP_PORT_END=$e
}

install_dependencies() {
    print "${GREEN}安装依赖工具...${NC}"
    apt-get update -y 2>/dev/null || true
    apt-get install -y curl wget qrencode openssl jq || yum install -y curl wget qrencode openssl jq
}

setup_firewall() {
    print "${GREEN}配置防火墙 + 端口跳跃...${NC}"
    iptables -I INPUT -p udp --dport $HY2_PORT -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p udp --dport $HOP_PORT_START:$HOP_PORT_END -j ACCEPT 2>/dev/null || true
    iptables -t nat -A PREROUTING -p udp --dport $HOP_PORT_START:$HOP_PORT_END -j REDIRECT --to-ports $HY2_PORT 2>/dev/null || true
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
}

create_config() {
    print "${GREEN}生成 sing-box 配置...${NC}"
    mkdir -p /etc/sing-box
    cat > /etc/sing-box/config.json << EOF
{
  "log": {"level": "info"},
  "inbounds": [{
    "type": "hysteria2",
    "listen": "::",
    "listen_port": $HY2_PORT,
    "users": [{"password": "$HY2_PASSWORD"}],
    "masquerade": "$MASQUERADE",
    "tls": ${DOMAIN:+{"enabled": true, "acme": {"domains": ["$DOMAIN"], "email": "$EMAIL"}}}
  }]
}
EOF
}

generate_client_qrcode() {
    print "${GREEN}🔄 生成客户端配置和二维码...${NC}"
    IP=$(curl -s4 ifconfig.me)
    SERVER=${DOMAIN:-$IP}
    
    cat > /root/hy2-client.yaml << EOF
server: $SERVER:$HY2_PORT,$HOP_PORT_START-$HOP_PORT_END

auth:
  type: password
  password: $HY2_PASSWORD

tls:
  sni: $SERVER
  insecure: false

transport:
  type: udp
  hopInterval: 30s
EOF

    qrencode -t ansiutf8 -l H < /root/hy2-client.yaml
    qrencode -t png -o /root/hy2-client.png < /root/hy2-client.yaml
    print "${GREEN}✅ 二维码已生成！${NC}"
}

setup_systemd() {
    print "${GREEN}设置开机自启...${NC}"
    cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=sing-box Service
After=network.target
[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now sing-box
}

# ====================== 主程序 ======================
check_root
interactive_settings
install_dependencies
bash <(curl -fsSL https://sing-box.app/install.sh)
setup_firewall
create_config
setup_systemd
generate_client_qrcode

print "${GREEN}🎉 安装完成！${NC}"
print "使用 ./singbox-multi-pro.sh menu 进入管理菜单"