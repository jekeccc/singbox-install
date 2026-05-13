#!/bin/bash
# =============================================
# sing-box 多协议一键安装脚本 (V2.0 优化版)
# =============================================

set -e

# ================== 初始参数 ==================
DOMAIN=""
EMAIL="admin@example.com"
HY2_PASSWORD=$(openssl rand -hex 16)
HY2_PORT=443
HOP_PORT_START=20000
HOP_PORT_END=30000
MASQUERADE="https://www.bing.com"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print() { echo -e "$1"; }

# [span_7](start_span)检查 Root[span_7](end_span)
check_root() { 
    [ "$(id -u)" -ne 0 ] && { print "${RED}错误: 请以 root 用户运行此脚本！${NC}"; exit 1; } 
}

# [span_8](start_span)增强型参数设置[span_8](end_span)
interactive_settings() {
    print "${GREEN}=== 基础配置设置 ===${NC}"
    read -p "请输入域名 (留空则使用 IP + 自签名证书): " DOMAIN
    
    get_port() {
        local prompt=$1; local default=$2; local var_name=$3
        while true; do
            read -p "$prompt [$default]: " val
            val=${val:-$default}
            if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 1 ] && [ "$val" -le 65535 ]; then
                eval "$var_name=$val"; break
            else
                print "${RED}请输入 1-65535 之间的数字！${NC}"
            fi
        done
    }

    get_port "主端口" "$HY2_PORT" "HY2_PORT"
    get_port "跳跃起始端口" "$HOP_PORT_START" "HOP_PORT_START"
    get_port "跳跃结束端口" "$HOP_PORT_END" "HOP_PORT_END"
}

# [span_9](start_span)安装依赖[span_9](end_span)
install_dependencies() {
    print "${GREEN}正在安装系统依赖...${NC}"
    apt update -y && apt install -y curl wget qrencode openssl jq uuid-runtime iptables-persistent || \
    yum install -y curl wget qrencode openssl jq iptables-services
}

# [span_10](start_span)[span_11](start_span)配置防火墙[span_10](end_span)[span_11](end_span)
setup_firewall() {
    print "${GREEN}配置防火墙规则与端口跳跃...${NC}"
    iptables -t nat -F PREROUTING || true
    iptables -I INPUT -p udp --dport $HY2_PORT -j ACCEPT
    iptables -I INPUT -p udp --dport $HOP_PORT_START:$HOP_PORT_END -j ACCEPT
    iptables -t nat -A PREROUTING -p udp --dport $HOP_PORT_START:$HOP_PORT_END -j REDIRECT --to-ports $HY2_PORT
    
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    else
        iptables-save > /etc/sysconfig/iptables || true
    fi
}

# [span_12](start_span)生成配置[span_12](end_span)
create_config() {
    print "${GREEN}正在生成 sing-box 服务端配置...${NC}"
    mkdir -p /etc/sing-box
    local TLS_JSON
    if [ -n "$DOMAIN" ]; then
        TLS_JSON='{"enabled": true, "server_name": "'$DOMAIN'", "acme": {"domains": ["'$DOMAIN'"], "email": "'$EMAIL'"}}'
    else
        print "${YELLOW}正在生成自签名证书...${NC}"
        openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/sing-box/server.key -out /etc/sing-box/server.crt -days 3650 -subj "/CN=bing.com"
        TLS_JSON='{"enabled": true, "certificate_path": "/etc/sing-box/server.crt", "key_path": "/etc/sing-box/server.key"}'
    fi

    cat > /etc/sing-box/config.json << EOF
{
  "log": {"level": "info"},
  "inbounds": [{
    "type": "hysteria2",
    "tag": "hy2-in",
    "listen": "::",
    "listen_port": $HY2_PORT,
    "users": [{"password": "$HY2_PASSWORD"}],
    "masquerade": "$MASQUERADE",
    "tls": $TLS_JSON
  }]
}
EOF
}

# [span_13](start_span)客户端信息[span_13](end_span)
generate_client_info() {
    print "${GREEN}=== 客户端配置信息 ===${NC}"
    local IP=$(curl -s4 ifconfig.me)
    local SERVER=${DOMAIN:-$IP}
    local INSECURE_VAL=$([ -z "$DOMAIN" ] && echo "1" || echo "0")
    local HY2_URI="hysteria2://$HY2_PASSWORD@$SERVER:$HY2_PORT?sni=$SERVER&mport=$HOP_PORT_START-$HOP_PORT_END&insecure=$INSECURE_VAL#SingBox-Hy2"

    print "${YELLOW}客户端链接 (URI):${NC}"
    print "${CYAN}$HY2_URI${NC}\n"
    echo "$HY2_URI" | qrencode -t ansiutf8
}

# [span_14](start_span)菜单[span_14](end_span)
management_menu() {
    while true; do
        print "\n${GREEN}======== sing-box 管理菜单 =======${NC}"
        print "1. 查看运行状态"
        print "2. 重启服务"
        print "3. 重新显示配置链接/二维码"
        print "0. 退出"
        read -p "请选择: " choice
        case $choice in
            1) systemctl status sing-box --no-pager ;;
            2) systemctl restart sing-box && print "${GREEN}已重启${NC}" ;;
            3) generate_client_info ;;
            0) exit 0 ;;
            *) print "${RED}无效选择${NC}" ;;
        esac
    done
}

main() {
    check_root
    interactive_settings
    install_dependencies
    bash <(curl -fsSL https://sing-box.app/install.sh)
    setup_firewall
    create_config
    cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=sing-box service
After=network.target
[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now sing-box
    generate_client_info
    print "\n${GREEN}安装完成！${NC}"
}

if [ "$1" = "menu" ]; then
    management_menu
else
    main "$@"
fi
