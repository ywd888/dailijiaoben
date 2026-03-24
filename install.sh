#!/bin/bash

# ====================================================
# Project: Sing-box Trojan One-Click (Optimized)
# Author: Gemini
# System: Debian/Ubuntu/CentOS
# ====================================================

CONFIG="/etc/sing-box/config.json"
CERT_DIR="/etc/sing-box"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 1. 权限检查
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行!${PLAIN}" && exit 1

# 2. 安装核心
install_core() {
    if ! command -v sing-box >/dev/null 2>&1; then
        echo -e "${YELLOW}正在安装 Sing-box...${PLAIN}"
        bash <(curl -fsSL https://sing-box.app/install.sh)
        systemctl enable sing-box
    fi
}

# 3. 获取公网 IP
get_ip() {
    local ip=$(curl -s4m 5 ipv4.icanhazip.com || curl -s4m 5 ifconfig.me)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s6m 5 ipv6.icanhazip.com || curl -s6m 5 ifconfig.me)
        echo "[$ip]"
    else
        echo "$ip"
    fi
}

# 4. 开放端口
open_port() {
    local port=$1
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $port/tcp >/dev/null 2>&1
        ufw allow $port/udp >/dev/null 2>&1
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$port/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=$port/udp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
}

# 5. 生成节点
gen_node() {
    install_core
    
    # 自动选择未占用端口
    while :; do
        PORT=$(shuf -i 20000-60000 -n 1)
        [[ $(ss -tuln | grep -w "$PORT") ]] || break
    done

    PASS=$(openssl rand -base64 12 | tr -d /=+ | cut -c1-16)
    read -p "请输入域名 (SNI, 默认 apps.apple.com): " SNI
    SNI=${SNI:-apps.apple.com}

    IP=$(get_ip)
    mkdir -p $CERT_DIR

    # 生成自签名证书
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout $CERT_DIR/key.pem -out $CERT_DIR/cert.pem \
        -subj "/CN=$SNI" >/dev/null 2>&1

    # 写入配置文件
    cat > $CONFIG <<EOF
{
  "log": {"level": "info"},
  "inbounds": [
    {
      "type": "trojan",
      "listen": "::",
      "listen_port": $PORT,
      "users": [{"password": "$PASS"}],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "certificate_path": "$CERT_DIR/cert.pem",
        "key_path": "$CERT_DIR/key.pem"
      }
    }
  ],
  "outbounds": [{"type": "direct"}]
}
EOF

    systemctl restart sing-box
    open_port $PORT

    LINK="trojan://$PASS@$IP:$PORT?security=tls&sni=$SNI&allowInsecure=1#Trojan-$(echo $IP | tr -d '[]')"

    echo -e "\n${GREEN}✅ 节点创建成功!${PLAIN}"
    echo -e "----------------------------------------"
    echo -e "${YELLOW}端口:${PLAIN} $PORT"
    echo -e "${YELLOW}密码:${PLAIN} $PASS"
    echo -e "${YELLOW}SNI:${PLAIN}  $SNI"
    echo -e "----------------------------------------"
    echo -e "${GREEN}节点链接:${PLAIN}"
    echo -e "$LINK"
    echo -e "----------------------------------------"
}

# 6. 删除节点
delete_node() {
    systemctl stop sing-box >/dev/null 2>&1
    systemctl disable sing-box >/dev/null 2>&1
    rm -rf /etc/sing-box
    echo -e "${RED}❌ 节点及配置已彻底删除${PLAIN}"
}

# 7. 查看节点
show_node() {
    if [ ! -f "$CONFIG" ]; then
        echo -e "${RED}❌ 错误: 未检测到配置文件!${PLAIN}"
        return
    fi
    # 使用简单正则提取（不依赖jq）
    local port=$(grep 'listen_port' $CONFIG | awk '{print $2}' | tr -d ', ')
    local pass=$(grep 'password' $CONFIG | awk -F'"' '{print $4}')
    local sni=$(grep 'server_name' $CONFIG | awk -F'"' '{print $4}')
    local ip=$(get_ip)

    LINK="trojan://$pass@$ip:$port?security=tls&sni=$sni&allowInsecure=1#Trojan-$(echo $ip | tr -d '[]')"
    
    echo -e "\n${GREEN}当前节点配置:${PLAIN}"
    echo -e "$LINK\n"
}

# 菜单循环
while true; do
    echo -e "${YELLOW}====== Trojan (Sing-box) 管理面板 ======${PLAIN}"
    echo -e "  1. 新建/重置节点"
    echo -e "  2. 删除节点"
    echo -e "  3. 查看当前链接"
    echo -e "  0. 退出"
    echo -e "========================================"
    read -p "请选择: " choice
    case $choice in
        1) gen_node ;;
        2) delete_node ;;
        3) show_node ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项!${PLAIN}" ;;
    esac
    echo -e "\n"
    read -n 1 -s -r -p "按任意键继续..."
    clear
done
