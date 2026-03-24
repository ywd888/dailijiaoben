#!/bin/bash
# ====================================================
# Sing-box Trojan + UDP Relay 一键安装
# Author: ywd888 & ChatGPT
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

CONFIG="/etc/sing-box/config.json"

check_env() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行!${PLAIN}" && exit 1
    command -v curl >/dev/null 2>&1 || { apt-get update && apt-get install -y curl || yum install -y curl; }
    command -v openssl >/dev/null 2>&1 || { apt-get install -y openssl || yum install -y openssl; }
}

get_ip() {
    local ip=$(curl -s4m 5 ipv4.icanhazip.com || curl -s4m 5 ifconfig.me)
    [[ -z "$ip" ]] && ip=$(curl -s6m 5 ipv6.icanhazip.com || curl -s6m 5 ifconfig.me)
    echo "$ip"
}

install_singbox() {
    if ! command -v sing-box >/dev/null 2>&1; then
        echo -e "${BLUE}正在安装 Sing-box...${PLAIN}"
        bash <(curl -fsSL https://sing-box.app/install.sh)
        systemctl enable sing-box
    fi
}

gen_node() {
    install_singbox

    while :; do
        PORT=$(shuf -i 20000-60000 -n 1)
        [[ $(ss -tuln | grep -w "$PORT") ]] || break
    done

    PASS=$(openssl rand -base64 12 | tr -d /=+ | cut -c1-16)
    read -p "请输入 SNI (默认 apps.apple.com): " SNI
    SNI=${SNI:-apps.apple.com}
    IP=$(get_ip)

    mkdir -p /etc/sing-box
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/sing-box/key.pem -out /etc/sing-box/cert.pem \
        -subj "/CN=$SNI" >/dev/null 2>&1

    cat > $CONFIG <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
    {
      "type": "trojan",
      "listen": "0.0.0.0",
      "listen_port": $PORT,
      "users": [{"password": "$PASS"}],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "certificate_path": "/etc/sing-box/cert.pem",
        "key_path": "/etc/sing-box/key.pem"
      }
    },
    {
      "type": "udp",
      "listen": "0.0.0.0",
      "listen_port": $PORT
    }
  ],
  "outbounds": [
    {"type": "direct"}
  ]
}
EOF

    systemctl restart sing-box

    # 防火墙放行
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $PORT/tcp
        ufw allow $PORT/udp
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$PORT/tcp
        firewall-cmd --permanent --add-port=$PORT/udp
        firewall-cmd --reload
    fi

    HOST=$IP
    [[ $IP == *":"* ]] && HOST="[$IP]"
    LINK="trojan://$PASS@$HOST:$PORT?security=tls&sni=$SNI&allowInsecure=1#Trojan-$IP"

    echo -e "\n${GREEN}✅ 部署成功!${PLAIN}"
    echo -e "${BLUE}Trojan 链接:${PLAIN} $LINK"
}

show_link() {
    if [ -f "$CONFIG" ]; then
        P=$(grep 'listen_port' $CONFIG | head -n1 | awk '{print $2}' | tr -d ', ')
        PW=$(grep 'password' $CONFIG | awk -F'"' '{print $4}')
        S=$(grep 'server_name' $CONFIG | awk -F'"' '{print $4}')
        I=$(get_ip)
        H=$I && [[ $I == *":"* ]] && H="[$I]"
        echo -e "${GREEN}trojan://$PW@$H:$P?security=tls&sni=$S&allowInsecure=1#Trojan-$I${PLAIN}"
    else
        echo -e "${RED}未安装节点${PLAIN}"
    fi
}

main() {
    check_env
    clear
    echo -e "${YELLOW}================================${PLAIN}"
    echo -e "   Sing-box Trojan + UDP 管理脚本   "
    echo -e "${YELLOW}================================${PLAIN}"
    echo -e "  1. 新建/重置节点"
    echo -e "  2. 删除节点"
    echo -e "  3. 查看当前链接"
    echo -e "  0. 退出"
    echo -e "${YELLOW}--------------------------------${PLAIN}"
    read -p "请选择: " choice

    case "$choice" in
        1) gen_node ;;
        2)
            systemctl stop sing-box >/dev/null 2>&1
            rm -rf /etc/sing-box
            echo -e "${RED}节点已删除${PLAIN}" ;;
        3) show_link ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${PLAIN}" ;;
    esac
}

main
