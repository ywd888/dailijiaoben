# Sing-box Trojan 一键安装脚本

这是一个基于 [Sing-box](https://github.com/SagerNet/sing-box) 核心的 Trojan 协议一键部署脚本。适用于 Debian / Ubuntu / CentOS 等主流 Linux 系统，支持 IPv4/IPv6 双栈。

## 🌟 特性
- **一键部署**：全自动安装 Sing-box 核心及配置环境。
- **智能兼容**：自动识别 IPv4 / IPv6 并生成适配链接。
- **防火墙适配**：自动放行 UFW 或 Firewalld 对应端口。
- **安全加固**：随机生成高强度密码及端口，支持自定义 SNI。
- **自签名证书**：内置 OpenSSL 自动生成 10 年期证书。

## 🚀 快速开始

在你的 VPS 终端执行以下命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ywd888/trojan/main/install.sh)
