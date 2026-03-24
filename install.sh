#!/bin/bash

# 默认配置
DOWNLOAD_URL="https://raw.githubusercontent.com/bqlpfy/ssr/refs/heads/master/ssserver"
DEFAULT_PASSWORD="Z6dcK1YS0BXW"
DEFAULT_PORT="15370"
BINARY_NAME="ssserver"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="ssserver"
CONFIG_FILE="/etc/ssserver/ssserver.conf"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

check_env() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}请使用 root 权限运行!${PLAIN}" && exit 1
    if ! command -v curl >/dev/null 2>&1; then
        apt-get update && apt-get install -y curl || yum install -y curl
    fi
}

install_ssserver() {
    echo -e "${BLUE}=== 安装 ssserver ===${PLAIN}"
    mkdir -p /etc/ssserver

    # 下载 ssserver
    if ! curl -L -o "$BINARY_NAME" "$DOWNLOAD_URL"; then
        echo -e "${RED}下载失败${PLAIN}"
        exit 1
    fi

    chmod +x "$BINARY_NAME"
    cp "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"

    # 创建 systemd 服务
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=SSServer Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=$INSTALL_DIR/$BINARY_NAME -c $CONFIG_FILE -U --tcp-fast-open
Restart=always
RestartSec=3
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
}

gen_node() {
    read -p "请输入密码 (默认 $DEFAULT_PASSWORD): " PASSWORD
    PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
    read -p "请输入端口 (默认 $DEFAULT_PORT): " PORT
    PORT=${PORT:-$DEFAULT_PORT}

    mkdir -p /etc/ssserver

    cat > "$CONFIG_FILE" <<EOF
{
    "server": "0.0.0.0",
    "server_port": $PORT,
    "password": "$PASSWORD",
    "method": "chacha20-ietf-poly1305",
    "timeout": 300,
    "fast_open": true,
    "workers": 1
}
EOF

    systemctl restart "$SERVICE_NAME"

    # 获取公网 IP
    IP=$(curl -s4m 5 ipv4.icanhazip.com || curl -s6m 5 ipv6.icanhazip.com)
    [[ $IP == *":"* ]] && HOST="[$IP]" || HOST="$IP"

    LINK="ss://$(echo -n "chacha20-ietf-poly1305:$PASSWORD@$HOST:$PORT" | base64 -w0)"
    echo -e "${GREEN}✅ 节点已生成${PLAIN}"
    echo -e "${BLUE}链接:${PLAIN} $LINK"
}

show_link() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}未安装节点${PLAIN}"
        return
    fi
    PORT=$(grep '"server_port"' $CONFIG_FILE | awk -F: '{gsub(/[ ,]/,"",$2); print $2}')
    PASSWORD=$(grep '"password"' $CONFIG_FILE | awk -F'"' '{print $4}')
    IP=$(curl -s4m 5 ipv4.icanhazip.com || curl -s6m 5 ipv6.icanhazip.com)
    [[ $IP == *":"* ]] && HOST="[$IP]" || HOST="$IP"

    LINK="ss://$(echo -n "chacha20-ietf-poly1305:$PASSWORD@$HOST:$PORT" | base64 -w0)"
    echo -e "${GREEN}当前节点链接:${PLAIN} $LINK"
}

main_menu() {
    check_env
    clear
    echo -e "${YELLOW}================================${PLAIN}"
    echo -e "    SSServer 管理脚本    "
    echo -e "${YELLOW}================================${PLAIN}"
    echo -e "1. 新建/重置节点"
    echo -e "2. 删除节点"
    echo -e "3. 查看节点链接"
    echo -e "0. 退出"
    echo -e "${YELLOW}--------------------------------${PLAIN"
    read -p "请选择: " choice

    case "$choice" in
        1) install_ssserver; gen_node ;;
        2) systemctl stop "$SERVICE_NAME"; rm -rf /etc/ssserver; echo -e "${RED}节点已删除${PLAIN}" ;;
        3) show_link ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${PLAIN}" ;;
    esac
}

main_menu
