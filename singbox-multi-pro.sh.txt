#!/bin/bash
# =============================================
# sing-box 多协议一键安装脚本 (V2.0 优化版)
# 支持 Hy2 端口跳跃 + URI 二维码 + 自动证书管理
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

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; [span_1](start_span)NC='\033[0m'[span_1](end_span)
print() { echo -e "$1"; [span_2](start_span)}

# 检查 Root[span_2](end_span)
check_root() { 
    [ "$(id -u)" -ne 0 ] && { print "${RED}错误: 请以 root 用户运行此脚本！${NC}"; exit 1; } 
[span_3](start_span)}

# 增强型参数设置[span_3](end_span)
interactive_settings() {
    print "${GREEN}=== 基础配置设置 ===${NC}"
    read -p "请输入域名 (留空则使用 IP + 自签名证书): " DOMAIN
    
    # 端口校验函数
    get_port() {
        local prompt=$1
        local default=$2
        local var_name=$3
        while true; do
            read -p "$prompt [$default]: " val
            val=${val:-$default}
            if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 1 ] && [ "$val" -le 65535 ]; then
                eval "$var_name=$val"
                break
            else
                print "${RED}请输入 1-65535 之间的数字！${NC}"
            fi
        done
    }

    get_port "主端口" "$HY2_PORT" "HY2_PORT"
    get_port "跳跃起始端口" "$HOP_PORT_START" "HOP_PORT_START"
    get_port "跳跃结束端口" "$HOP_PORT_END" "HOP_PORT_END"
}

# [span_4](start_span)安装依赖增加持久化工具[span_4](end_span)
install_dependencies() {
    print "${GREEN}正在安装系统依赖...${NC}"
    apt update -y && apt install -y curl wget qrencode openssl jq uuid-runtime iptables-persistent || \
    yum install -y curl wget qrencode openssl jq iptables-services
}

# 优化防火墙配置：增加清理逻辑与持久化
setup_firewall() {
    print "${GREEN}配置防火墙规则与端口跳跃...${NC}"
    # 清理旧的 NAT 规则防止重复堆积
    iptables -t nat -F PREROUTING || true
    
    # 放行主端口与跳跃区间
    iptables -I INPUT -p udp --dport $HY2_PORT -j ACCEPT
    iptables -I INPUT -p udp --dport $HOP_PORT_START:$HOP_PORT_END -j ACCEPT
    
    # 核心跳转逻辑
    iptables -t nat -A PREROUTING -p udp --dport $HOP_PORT_START:$HOP_PORT_END -j REDIRECT --to-ports $HY2_PORT
    
    # 保存规则（Debian/Ubuntu 自动持久化）
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    else
        iptables-save > /etc/sysconfig/iptables || true
    fi
}

# [span_5](start_span)智能生成服务端配置[span_5](end_span)
create_config() {
    print "${GREEN}正在生成 sing-box 服务端配置...${NC}"
    mkdir -p /etc/sing-box
    
    local TLS_JSON
    if [ -n "$DOMAIN" ]; then
        # 域名模式：使用 ACME
        TLS_JSON='{"enabled": true, "server_name": "'$DOMAIN'", "acme": {"domains": ["'$DOMAIN'"], "email": "'$EMAIL'"}}'
    else
        # IP 模式：生成自签名证书
        print "${YELLOW}未检测到域名，正在生成自签名证书...${NC}"
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

# [span_6](start_span)生成 URI 与二维码（兼容性最高）[span_6](end_span)
generate_client_info() {
    print "${GREEN}=== 客户端配置信息 ===${NC}"
    local IP=$(curl -s4 ifconfig.me)
    local SERVER=${DOMAIN:-$IP}
    
    # [span_7](start_span)构造标准的 Hysteria2 URI[span_7](end_span)
    # 参数含义：mport=跳跃端口, sni=域名, insecure=是否允许非法证书
    local INSECURE_VAL=$([ -z "$DOMAIN" ] && echo "1" || echo "0")
    local HY2_URI="hysteria2://$HY2_PASSWORD@$SERVER:$HY2_PORT?sni=$SERVER&mport=$HOP_PORT_START-$HOP_PORT_END&insecure=$INSECURE_VAL#SingBox-Hy2"

    print "${YELLOW}客户端链接 (URI):${NC}"
    print "${CYAN}$HY2_URI${NC}\n"
    
    print "${YELLOW}客户端二维码 (支持小火箭/Sing-box 扫码):${NC}"
    echo "$HY2_URI" | qrencode -t ansiutf8
    
    # 同时保留原始 YAML 配置供参考
    cat > /root/hy2-client.yaml << EOF
server: $SERVER:$HY2_PORT,$HOP_PORT_START-$HOP_PORT_END
auth: $HY2_PASSWORD
tls:
  sni: $SERVER
  insecure: $([ -z "$DOMAIN" ] && echo "true" || echo "false")
EOF
}

# [span_8](start_span)菜单管理[span_8](end_span)
management_menu() {
    while true; do
        print "\n${GREEN}======== sing-box 管理菜单 =======${NC}"
        print "1. 查看运行状态"
        print "2. 重启服务"
        print "3. 重新显示配置链接/二维码"
        print "4. 修改端口跳跃设置"
        print "0. 退出"
        read -p "请选择: " choice
        case $choice in
            1) systemctl status sing-box --no-pager ;;
            2) systemctl restart sing-box && print "${GREEN}已重启${NC}" ;;
            3) generate_client_info ;;
            4) interactive_settings && setup_firewall && create_config && systemctl restart sing-box ;;
            0) exit 0 ;;
            *) print "${RED}无效选择${NC}" ;;
        esac
    done
}

# [span_9](start_span)主流程[span_9](end_span)
main() {
    check_root
    interactive_settings
    install_dependencies
    # 调用官方安装脚本
    bash <(curl -fsSL https://sing-box.app/install.sh)
    setup_firewall
    create_config
    
    # [span_10](start_span)配置 systemd[span_10](end_span)
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
    print "提示：如果无法连接，请确认你的云服务商控制台安全组已放行 UDP $HY2_PORT 以及 $HOP_PORT_START-$HOP_PORT_END"
}

# 启动
if [ "$1" = "menu" ]; then
    management_menu
else
    main "$@"
fi
