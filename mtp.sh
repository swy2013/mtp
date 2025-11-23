#!/bin/bash

# MTProto Proxy 一键安装脚本
# 支持: CentOS 7+, Ubuntu 16.04+, Debian 9+

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查系统
check_system() {
    if [[ -f /etc/redhat-release ]]; then
        SYSTEM="centos"
    elif grep -q "Ubuntu" /etc/issue; then
        SYSTEM="ubuntu"
    elif grep -q "Debian" /etc/issue; then
        SYSTEM="debian"
    else
        log_error "不支持的系统"
        exit 1
    fi
    log_info "检测到系统: $SYSTEM"
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖..."
    
    if [[ $SYSTEM == "centos" ]]; then
        yum update -y
        yum install -y epel-release
        yum install -y curl wget git openssl-devel zlib-devel openssl python3
    else
        apt-get update
        apt-get install -y curl wget git build-essential libssl-dev zlib1g-dev openssl python3
    fi
}

# 生成随机密钥
generate_secret() {
    openssl rand -hex 16
}

# 安装 MTProto Proxy
install_mtproto() {
    log_info "安装 MTProto Proxy..."
    
    cd /tmp
    git clone https://github.com/TelegramMessenger/MTProxy
    cd MTProxy
    
    make -j$(nproc)
    cp objs/bin/mtproto-proxy /usr/local/bin/
    
    # 创建配置目录
    mkdir -p /etc/mtproto-proxy
}

# 生成配置文件
generate_config() {
    log_info "生成配置文件..."
    
    # 生成随机密钥
    SECRET=$(generate_secret)
    log_info "生成密钥: $SECRET"
    
    # 获取公网IP（如果没有设置DOMAIN）
    PUBLIC_IP=$(curl -s -4 ip.sb)
    
    # 创建配置文件
    cat > /etc/mtproto-proxy/config.py << EOF
PORT = 443

# name -> secret (32 hex chars)
USERS = {
    "tg": "$SECRET",
}

MODES = {
    "classic": False,
    "secure": False,
    "tls": True
}

# 可选: 设置TLS域名
# TLS_DOMAIN = "www.google.com"

# 可选: 广告标签 (从 @MTProxybot 获取)
# AD_TAG = ""
EOF

    # 创建systemd服务
    cat > /etc/systemd/system/mtproto-proxy.service << EOF
[Unit]
Description=MTProto Proxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/mtproto-proxy
ExecStart=/usr/local/bin/mtproto-proxy -u nobody -p 8888 -H 443 -S $SECRET --aes-pwd proxy-secret proxy-multi.conf -M 1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

# 配置防火墙
setup_firewall() {
    log_info "配置防火墙..."
    
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 443/tcp
        ufw reload
        log_info "UFW 防火墙已配置"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --reload
        log_info "FirewallD 已配置"
    elif command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT
        # 保存iptables规则
        if command -v iptables-save >/dev/null 2>&1; then
            iptables-save > /etc/iptables.rules
        fi
        log_info "iptables 已配置"
    else
        log_warn "未找到防火墙工具，请手动开放端口 443"
    fi
}

# 启动服务
start_service() {
    log_info "启动 MTProto Proxy 服务..."
    
    systemctl daemon-reload
    systemctl enable mtproto-proxy
    systemctl start mtproto-proxy
    
    sleep 2
    
    if systemctl is-active --quiet mtproto-proxy; then
        log_info "MTProto Proxy 启动成功"
    else
        log_error "MTProto Proxy 启动失败"
        journalctl -u mtproto-proxy -n 10 --no-pager
        exit 1
    fi
}

# 显示配置信息
show_info() {
    SECRET=$(grep -o '"tg": "[^"]*' /etc/mtproto-proxy/config.py | cut -d'"' -f4)
    PUBLIC_IP=$(curl -s -4 ip.sb)
    
    echo
    log_info "=== MTProto Proxy 安装完成 ==="
    echo
    log_info "代理地址: $PUBLIC_IP:443"
    log_info "代理密钥: $SECRET"
    echo
    log_info "Telegram 客户端配置:"
    echo "tg://proxy?server=$PUBLIC_IP&port=443&secret=$SECRET"
    echo
    log_info "管理命令:"
    echo "启动: systemctl start mtproto-proxy"
    echo "停止: systemctl stop mtproto-proxy"
    echo "重启: systemctl restart mtproto-proxy"
    echo "状态: systemctl status mtproto-proxy"
    echo "日志: journalctl -u mtproto-proxy -f"
    echo
}

# 主函数
main() {
    log_info "开始安装 MTProto Proxy..."
    
    check_system
    install_dependencies
    install_mtproto
    generate_config
    setup_firewall
    start_service
    show_info
    
    log_info "安装完成!"
}

# 运行主函数
main "$@"