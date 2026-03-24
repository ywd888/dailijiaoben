#!/bin/bash

# ====================================================
# Project: Sing-box Trojan One-Click
# Description: A simple script to deploy Trojan node via Sing-box
# Author: YourName (via Gemini)
# GitHub: https://github.com/your-username/your-repo
# ====================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

CONFIG_FILE="/etc/sing-box/config.json"
CERT_DIR="/etc/sing-box"

# 检查 Root 权限
[[ $EUID -ne 0 ]] && echo -e "${RED}Error: This script must be run as root!${PLAIN}" && exit 1

# 检查并安装基础依赖
install_base() {
    echo -e "${BLUE}检查系统依赖...${PLAIN}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y curl openssl socat 
    elif command -v yum >/dev/null 2>&1; then
        yum makecache && yum install -y curl openssl socat
    fi
}

# 安装 Sing-box 核心
install_singbox() {
    if ! command -v sing-box >/dev/null 2>&1; then
        echo -e "${YELLOW}正在通过官方脚本安装 Sing-box...${PLAIN}"
        bash <(curl -fsSL https://sing-box.app/install.sh)
        systemctl enable sing-box
    else
        echo -e "${GREEN}Sing-box 已安装，跳过。${PLAIN}"
    fi
}

# 获取公网 IP (兼容 IPv4/IPv6)
get_ip() {
    local ip=$(curl -s4m 5 ipv4.icanhazip.com || curl -s4m 5 ifconfig.me)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s6m 5 ipv6.icanhazip.com || curl -s6m 5 ifconfig.me)
        echo "[$ip]"
    else
        echo "$ip"
    fi
}

# 智能防火墙策略
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

# 生成配置
create_node() {
    install_base
    install_singbox

    # 自动获取可用端口
    while :; do
        PORT=$(shuf -i 20000-60000 -n 1)
        [[ $(ss -tuln | grep -w "$PORT") ]] || break
    done

    # 交互输入
    echo -e "${BLUE}--- 节点配置 ---${PLAIN}"
    read -p "请输入伪装域名 (SNI, 默认 apps.apple.com): " SNI
    SNI=${SNI:-apps.apple.com}
    
    PASS=$(openssl rand -base64 12 | tr -d /=+ | cut -c1-16)
    IP=$(get_ip)

    # 证书处理
    mkdir -p $CERT_DIR
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout $CERT_DIR/key.pem -out $CERT_DIR/cert.pem \
        -subj "/CN=$SNI" >/dev/null 2>&1

    # 生成标准 JSON
    cat > $CONFIG_FILE <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        {
          "password": "$PASS"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "certificate_path": "$CERT_DIR/cert.pem",
        "key_path": "$CERT_DIR/key.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    # 启动服务
    systemctl restart sing-box
    open_port $PORT

    # 生成链接
    # 注意：自签名证书必须带 allowInsecure=1
    LINK="trojan://$PASS@$IP:$PORT?security=tls&sni=$SNI&allowInsecure=1#Trojan-$(echo $IP | tr -d '[]')"

    clear
    echo -e "${GREEN}🎉 部署完成!${PLAIN}"
    echo -e "------------------------------------------------"
    echo -e "${BLUE}端口:${PLAIN} $PORT"
    echo -e "${BLUE}密码:${PLAIN} $PASS"
    echo -e "${BLUE}SNI:${PLAIN}  $SNI"
    echo -e "------------------------------------------------"
    echo -e "${GREEN}节点链接 (复制到客户端):${PLAIN}"
    echo -e "${YELLOW}$LINK${PLAIN}"
    echo -e "------------------------------------------------"
}

# 删除
uninstall_node() {
    read -p "确认卸载 Sing-box 及所有配置吗? [y/n]: " conf
    if [[ "$conf" == "y" ]]; then
        systemctl stop sing-box >/dev/null 2>&1
        systemctl disable sing-box >/dev/null 2>&1
        rm -rf /etc/sing-box
        echo -e "${RED}卸载成功。${PLAIN}"
    fi
}

# 菜单
menu() {
    echo -e "
  ${GREEN}Sing-box Trojan 一键脚本${PLAIN}
  ${BLUE}========================${PLAIN}
  ${GREEN}1.${PLAIN} 安装/重置节点
  ${GREEN}2.${PLAIN} 查看节点链接
  ${GREEN}3.${PLAIN} 彻底卸载节点
  ${GREEN}0.${PLAIN} 退出
  "
    read -p "请选择: " choice
    case $choice in
        1) create_node ;;
        2) 
            if [ -f "$CONFIG_FILE" ]; then
                # 简单解析逻辑
                local p=$(grep 'listen_port' $CONFIG_FILE | awk '{print $2}' | tr -d ', ')
                local pw=$(grep 'password' $CONFIG_FILE | awk -F'"' '{print $4}')
                local s=$(grep 'server_name' $CONFIG_FILE | awk -F'"' '{print $4}')
                local i=$(get_ip)
                echo -e "${YELLOW}trojan://$pw@$i:$p?security=tls&sni=$s&allowInsecure=1#Trojan-$(echo $i | tr -d '[]')${PLAIN}"
            else
                echo -e "${RED}未发现配置文件。${PLAIN}"
            fi
            ;;
        3) uninstall_node ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
}

menu
