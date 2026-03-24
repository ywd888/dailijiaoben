#!/bin/bash

# ====================================================
# Project: Sing-box Trojan One-Click
# Author: ywd888
# Repo: https://github.com/ywd888/trojan
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

CONFIG="/etc/sing-box/config.json"

check_env() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行!${PLAIN}" && exit 1
    if ! command -v curl >/dev/null 2>&1; then
        apt-get update && apt-get install -y curl || yum install -y -y curl
    fi
}

get_ip() {
    local ip=$(curl -s4m 5 ipv4.icanhazip.com || curl -s4m 5 ifconfig.me)
    [[ -z "$ip" ]] && ip=$(curl -s6m 5 ipv6.icanhazip.com || curl -s6m 5 ifconfig.me)
    echo "$ip"
}

gen_node() {
    if ! command -v sing-box >/dev/null 2>&1; then
        echo -e "${BLUE}正在安装 Sing-box...${PLAIN}"
        bash <(curl -fsSL https://sing-box.app/install.sh)
        systemctl enable sing-box
    fi

    # 随机端口
    while :; do
        PORT=$(shuf -i 20000-60000 -n 1)
        [[ $(ss -tuln | grep -w "$PORT") ]] || break
    done

    PASS=$(openssl rand -base64 12 | tr -d /=+ | cut -c1-16)
    read -p "请输入 SNI (默认 apps.apple.com): " SNI
    SNI=${SNI:-apps.apple.com}
    IP=$(get_ip)

    mkdir -p /etc/sing-box

    # 自签证书
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/sing-box/key.pem -out /etc/sing-box/cert.pem \
        -subj "/CN=$SNI" >/dev/null 2>&1

    # 配置 JSON
    cat > $CONFIG <<EOF
{
  "log": {"level": "info"},
  "inbounds": [{
    "type": "trojan",
    "listen": ["0.0.0.0","::"],
    "listen_port": $PORT,
    "users": [{"password": "$PASS"}],
    "tls": {
      "enabled": true,
      "server_name": "$SNI",
      "certificate_path": "/etc/sing-box/cert.pem",
      "key_path": "/etc/sing-box/key.pem"
    }
  }],
  "outbounds": [{"type": "direct"}]
}
EOF

    systemctl restart sing-box

    # 防火墙开放 TCP + UDP
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $PORT/tcp >/dev/null 2>&1
        ufw allow $PORT/udp >/dev/null 2>&1
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$PORT/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=$PORT/udp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi

    # 链接生成
    HOST=$IP
    [[ $IP == *":"* ]] && HOST="[$IP]"
    LINK="trojan://$PASS@$HOST:$PORT?security=tls&sni=$SNI&allowInsecure=1#Trojan-$IP"

    echo -e "\n${GREEN}✅ 部署成功!${PLAIN}"
    echo -e "${BLUE}节点链接:${PLAIN} $LINK"
}

show_link() {
    if [ -f "$CONFIG" ]; then
        P=$(grep 'listen_port' $CONFIG | awk '{print $2}' | tr -d ', ')
        PW=$(grep 'password' $CONFIG | awk -F'"' '{print $4}')
        S=$(grep 'server_name' $CONFIG | awk -F'"' '{print $4}')
        I=$(get_ip)
        H=$I && [[ $I == *":"* ]] && H="[$I]"
        echo -e "${GREEN}trojan://$PW@$H:$P?security=tls&sni=$S&allowInsecure=1#Trojan-$I${PLAIN}"
    else
        echo -e "${RED}未安装节点${PLAIN}"
    fi
}

delete_node() {
    systemctl stop sing-box >/dev/null 2>&1
    rm -rf /etc/sing-box
    echo -e "${RED}节点已删除${PLAIN}"
}

menu() {
    echo -e "${YELLOW}====== Sing-box Trojan 管理 ======${PLAIN}"
    echo -e "1. 新建/重置节点"
    echo -e "2. 彻底删除节点"
    echo -e "3. 查看当前节点链接"
    echo -e "0. 退出"
    echo -e "${YELLOW}================================${PLAIN}"
}

main() {
    check_env
    while true; do
        clear
        menu
        read -p "请选择: " choice
        case "$choice" in
            1) gen_node ;;
            2) delete_node ;;
            3) show_link ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项${PLAIN}" ;;
        esac
        read -p "按回车继续..."
    done
}

main
