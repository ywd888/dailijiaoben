#!/bin/bash

DOWNLOAD_URL="https://raw.githubusercontent.com/ywd888/dailijiaoben"
BINARY_NAME="ssserver"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="ssserver"
DEFAULT_PASSWORD="Z6dcK1YS0BXW"
DEFAULT_PORT="15370"

check_root() {
    [[ $EUID -ne 0 ]] && echo "错误: 请使用 root 权限运行!" && exit 1
}

enable_tfo() {
    local tfo=$(cat /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null || echo 0)
    [[ $tfo -lt 3 ]] && echo 3 > /proc/sys/net/ipv4/tcp_fastopen
    grep -q "net.ipv4.tcp_fastopen" /etc/sysctl.conf || echo "net.ipv4.tcp_fastopen=3" >> /etc/sysctl.conf
}

install_binary() {
    curl -L -o "$BINARY_NAME" "$DOWNLOAD_URL" || { echo "下载失败"; exit 1; }
    chmod +x "$BINARY_NAME"
    cp "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
}

create_service() {
    cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=SSServer Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=$INSTALL_DIR/$BINARY_NAME -s [::]:$PORT -k $PASSWORD -m chacha20-ietf-poly1305 -U --tcp-fast-open
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
}

gen_node() {
    read -p "请输入节点密码 (默认 $DEFAULT_PASSWORD): " PASSWORD
    PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}
    read -p "请输入节点端口 (默认 $DEFAULT_PORT): " PORT
    PORT=${PORT:-$DEFAULT_PORT}

    install_binary
    create_service

    echo -e "\n✅ 节点已创建!"
    echo -e "SS 链接 (可复制):"
    local IP=$(curl -s4 ipv4.icanhazip.com)
    echo "ss://${PASSWORD}@${IP}:${PORT}?encrypt=chacha20-ietf-poly1305#SS-$IP"
}

show_node() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        local IP=$(curl -s4 ipv4.icanhazip.com)
        echo "ss://${PASSWORD}@${IP}:${PORT}?encrypt=chacha20-ietf-poly1305#SS-$IP"
    else
        echo "节点未启动"
    fi
}

menu() {
    while true; do
        echo ""
        echo "=== SSServer 节点管理 ==="
        echo "1. 新建节点"
        echo "2. 查看当前节点链接"
        echo "0. 退出"
        read -p "请选择: " choice
        case "$choice" in
            1) gen_node ;;
            2) show_node ;;
            0) exit 0 ;;
            *) echo "无效选项" ;;
        esac
    done
}

check_root
enable_tfo
menu
