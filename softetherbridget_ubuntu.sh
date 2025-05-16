#!/bin/bash
# Softether VPN Bridge for Ubuntu 24.04
# 作者：DengCaiPing
# 微信：51529502
# 时间：2025-05-15
# 版本：v1.1

# 系统环境变量
IPWAN=$(curl -4 ifconfig.io)  # 设置为固定公网IP
SERVER_IP=$IPWAN
USER="pi"
SERVER_PASSWORD="xiaojie"
SHARED_KEY="xiaojie"
HUB="PiNodeHub"
HUB_PASSWORD=${SERVER_PASSWORD}
USER_PASSWORD=${SERVER_PASSWORD}
TARGET="/usr/local/"

# 网络配置
LOCAL_IP="192.168.100.1"
DCP_DNS="8.8.8.8"
DCP_STATIC="192.168.100.2"
# 确保DHCP只分配固定IP
DHCP_MIN="192.168.100.2"
DHCP_MAX="192.168.100.2"

# 卸载函数
Uninstall() {
    echo "开始卸载SoftEther VPN..."
    # 停止并禁用服务
    systemctl stop vpnserver rinetd
    systemctl disable vpnserver rinetd
    # 删除服务文件
    rm -f /etc/systemd/system/vpnserver.service
    # 删除安装目录
    rm -rf ${TARGET}vpnserver
    # 删除配置文件
    rm -f /etc/rinetd.conf
    rm -f /etc/dnsmasq.conf
    # 停止并禁用dnsmasq服务
    systemctl stop dnsmasq
    systemctl disable dnsmasq
    # 删除系统优化配置
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    sed -i '/net.core.somaxconn/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
    sed -i '/\* soft nofile/d' /etc/security/limits.conf
    sed -i '/\* hard nofile/d' /etc/security/limits.conf
    echo "SoftEther VPN已成功卸载！"
    exit 0
}

# 密码验证函数
DSetup() {
    clear
    echo "==========================================================="
    echo "====Softether一键安装脚本(Ubuntu专用)  微信：15521188891====="
    echo "============================================================"
    echo ""
    stty erase ^H
    local DcpPass=515900
    read -p "请输入密码：" PASSWD
    if [ "$PASSWD" == "$DcpPass" ]; then
        :
    else
        echo "密码错误，请重新输入！"
        DSetup
    fi
}

# 安装VPN函数
InstallVPN() {
    echo "开始安装 SoftEther VPN Server..."

    # 配置软件源
    echo "开始配置软件源..."
    cat > /etc/apt/sources.list << EOF
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
EOF

    # 更新系统并安装依赖
    echo "开始安装依赖..."
    apt update && apt upgrade -y
    DEBIAN_FRONTEND=noninteractive apt install -y build-essential wget expect zlib1g-dev libssl-dev net-tools rinetd dnsmasq

    # 下载并安装最新版本的SoftEther VPN Server
    echo "开始下载并安装最新版本的SoftEther VPN Server..."
    cd ${TARGET}
    wget https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/releases/download/v4.42-9798-rtm/softether-vpnserver-v4.42-9798-rtm-2023.06.30-linux-x64-64bit.tar.gz
    tar xzf softether-vpnserver-v4.42-9798-rtm-2023.06.30-linux-x64-64bit.tar.gz -C ${TARGET}
    rm -f softether-vpnserver-v4.42-9798-rtm-2023.06.30-linux-x64-64bit.tar.gz

    # 编译安装
    echo "开始编译安装..."
    cd ${TARGET}vpnserver
    cat > build.expect << EOF
#!/usr/bin/expect
set timeout 300
spawn make
expect "number:"
send "1\r"
expect "number:"
send "1\r"
expect "number:"
send "1\r"
expect eof
EOF
    chmod +x build.expect
    ./build.expect

    # 设置权限
    echo "开始设置权限..."
    chmod 600 ${TARGET}vpnserver/*
    chmod 700 ${TARGET}vpnserver/vpnserver ${TARGET}vpnserver/vpncmd

    # 创建systemd服务
    echo "开始创建systemd服务..."
    cat > /etc/systemd/system/vpnserver.service << EOF
[Unit]
Description=SoftEther VPN Server
After=network.target

[Service]
Type=forking
ExecStart=${TARGET}vpnserver/vpnserver start
ExecStop=${TARGET}vpnserver/vpnserver stop
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # 启用IP转发
    echo "开始配置IP转发..."
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/ipv4_forwarding.conf
    sysctl --system

    # 启动VPN服务器并检查状态
    echo "开始启动VPN服务器并检查状态..."
    systemctl daemon-reload
    systemctl enable vpnserver
    systemctl start vpnserver
    sleep 10  # 等待服务器启动
    if ! systemctl is-active --quiet vpnserver; then
        echo "错误：VPN服务器启动失败"
        systemctl status vpnserver
        exit 1
    fi

    # 配置VPN服务器 
    echo "开始配置VPN服务器..." 
    # 设置服务器密码并验证 
    ${TARGET}vpnserver/vpncmd localhost /SERVER /CMD ServerPasswordSet ${SERVER_PASSWORD} 
    if ! ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD About; then 
        echo "错误：服务器密码设置失败，请检查密码" 
        echo "尝试重新设置密码..." 
        ${TARGET}vpnserver/vpncmd localhost /SERVER /CMD ServerPasswordSet ${SERVER_PASSWORD} 
        sleep 2 
        if ! ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD About; then 
            echo "错误：服务器密码设置仍然失败，请检查VPN服务器状态" 
            systemctl status vpnserver 
            exit 1 
        fi 
    fi 
    # 创建HUB并验证 
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD HubCreate ${HUB} /PASSWORD:${HUB_PASSWORD} 
    if ! ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD Hub ${HUB}; then 
        echo "错误：HUB创建失败，请检查密码" 
        exit 1 
    fi 
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD UserCreate ${USER} /GROUP:none /REALNAME:none /NOTE:none 
    # 设置用户密码并验证 
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD UserPasswordSet ${USER} /PASSWORD:${USER_PASSWORD} 
    if ! ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD UserGet ${USER}; then 
        echo "错误：用户创建或密码设置失败，请检查密码" 
        exit 1 
    fi 
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD IPsecEnable /L2TP:yes /L2TPRAW:yes /ETHERIP:yes /PSK:${SHARED_KEY} /DEFAULTHUB:${HUB} 
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD BridgeCreate ${HUB} /DEVICE:soft /TAP:yes
    
    # 配置tap_soft接口
    echo "配置tap_soft接口..."
    # 等待tap_soft接口创建完成
    echo "等待tap_soft接口创建..."
    for i in {1..30}; do
        if ip link show tap_soft > /dev/null 2>&1; then
            echo "tap_soft接口已创建成功"
            break
        fi
        echo "等待tap_soft接口创建，尝试 $i/30..."
        sleep 2
    done
    
    # 确认接口存在后再配置
    if ip link show tap_soft > /dev/null 2>&1; then
        ip addr add ${LOCAL_IP}/24 dev tap_soft
        ip link set tap_soft up
        echo "tap_soft接口配置完成"
    else
        echo "错误：tap_soft接口创建失败，尝试手动创建..."
        # 尝试重新创建桥接
        ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD BridgeCreate ${HUB} /DEVICE:soft /TAP:yes
        sleep 5
        if ip link show tap_soft > /dev/null 2>&1; then
            ip addr add ${LOCAL_IP}/24 dev tap_soft
            ip link set tap_soft up
            echo "tap_soft接口手动创建并配置完成"
        else
            echo "严重错误：无法创建tap_soft接口，请手动检查"
        fi
    fi
    
    # 配置dnsmasq
    echo "配置dnsmasq..."
    # 备份原始配置文件
    if [ -f /etc/dnsmasq.conf ]; then
        cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
    fi
    
    # 创建dnsmasq配置文件
    cat > /etc/dnsmasq.conf << EOF
# dnsmasq配置文件
# 基本设置
interface=tap_soft
bind-interfaces
domain-needed
bogus-priv

# DNS设置
server=${DCP_DNS}
server=8.8.4.4

# DHCP设置
dhcp-range=${DHCP_MIN},${DHCP_MAX},255.255.255.0,24h
dhcp-option=option:router,${LOCAL_IP}
dhcp-option=option:dns-server,${LOCAL_IP}

# 固定IP分配 - 确保MAC地址格式正确
#dhcp-host=00:00:00:00:00:01,${DCP_STATIC},infinite

# 日志设置
log-queries
log-dhcp
EOF
    
    # 启动dnsmasq服务
    # 确保tap_soft接口存在后再启动dnsmasq
    if ip link show tap_soft > /dev/null 2>&1; then
        # 确保dnsmasq配置正确
        echo "检查dnsmasq配置..."
        dnsmasq --test
        if [ $? -ne 0 ]; then
            echo "dnsmasq配置有误，尝试修复..."
            # 尝试使用更简单的配置
            cat > /etc/dnsmasq.conf << EOF
# 简化的dnsmasq配置
interface=tap_soft
bind-interfaces
domain-needed
bogus-priv
server=${DCP_DNS}
server=8.8.4.4
dhcp-range=${DHCP_MIN},${DHCP_MAX},255.255.255.0,24h
dhcp-option=option:router,${LOCAL_IP}
dhcp-option=option:dns-server,${LOCAL_IP}
EOF
        fi
        
        # 重启dnsmasq服务
        systemctl restart dnsmasq
        systemctl enable dnsmasq
        
        # 检查服务状态
        if ! systemctl is-active --quiet dnsmasq; then
            echo "警告：dnsmasq服务启动失败，但将继续执行其他配置"
            systemctl status dnsmasq
        else
            echo "dnsmasq服务启动成功"
        fi
    else
        echo "警告：tap_soft接口不存在，无法启动dnsmasq服务"
    fi

    # 配置网络转发规则和IPv4优先级
    iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
    
    # 添加防火墙规则允许端口访问
    echo "开始配置防火墙规则..."
    # 安装防火墙工具
    DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
    
    # 允许VPN相关端口
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p tcp --dport 992 -j ACCEPT
    iptables -A INPUT -p tcp --dport 5555 -j ACCEPT
    iptables -A INPUT -p udp --dport 500 -j ACCEPT
    iptables -A INPUT -p udp --dport 4500 -j ACCEPT
    iptables -A INPUT -p udp --dport 1701 -j ACCEPT
    
    # 允许Pi-Node节点端口
    for port in $(seq 31400 31409); do
        iptables -A INPUT -p tcp --dport $port -j ACCEPT
    done
    
    # 保存防火墙规则
    netfilter-persistent save

    # 验证并配置tap_soft接口
    echo "验证并配置tap_soft接口..."
    if ! ip link show tap_soft > /dev/null 2>&1; then
        echo "警告：tap_soft接口未创建成功，尝试重新启动VPN服务..."
        systemctl restart vpnserver
        sleep 10
        # 再次尝试创建桥接
        ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD BridgeCreate ${HUB} /DEVICE:soft /TAP:yes
        sleep 5
        
        if ! ip link show tap_soft > /dev/null 2>&1; then
            echo "错误：无法创建tap_soft接口，但将继续执行其他配置"
        fi
    fi
    
    # 如果接口存在，确保配置正确
    if ip link show tap_soft > /dev/null 2>&1; then
        ip addr flush dev tap_soft
        ip addr add ${LOCAL_IP}/24 dev tap_soft
        ip link set tap_soft up
        echo "tap_soft接口配置已更新"
    fi

    # 系统优化配置
    echo "开始系统优化配置..."
    echo "* soft nofile 1048576" >> /etc/security/limits.conf
    echo "* hard nofile 1048576" >> /etc/security/limits.conf
    echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_max_syn_backlog = 65535" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_max_tw_buckets = 1440000" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_fin_timeout = 15" >> /etc/sysctl.conf
    sysctl -p

    # VPN服务器性能优化
    echo "开始VPN服务器性能优化..."
    # 使用正确的命令名称
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD ServerCertRegenerate 4096
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD ServerCipherSet ECDHE-RSA-AES256-GCM-SHA384
    
    # 设置Hub级别的会话数
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD SetMaxSession 50000
    
    # 设置服务器级别的会话数
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD SetMaxSession 100000
    
    # 设置其他性能参数
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD KeepDisable
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD VpnOverIcmpDnsEnable /ICMP:yes /DNS:yes

    # 配置端口映射
    echo "开始配置端口映射..."
    cat > /etc/rinetd.conf << EOF
# Pi-Node节点端口转发
# 格式: 外部IP 外部端口 内部IP 内部端口
${IPWAN} 31400 ${DCP_STATIC} 31400
${IPWAN} 31401 ${DCP_STATIC} 31401
${IPWAN} 31402 ${DCP_STATIC} 31402
${IPWAN} 31403 ${DCP_STATIC} 31403
${IPWAN} 31404 ${DCP_STATIC} 31404
${IPWAN} 31405 ${DCP_STATIC} 31405
${IPWAN} 31406 ${DCP_STATIC} 31406
${IPWAN} 31407 ${DCP_STATIC} 31407
${IPWAN} 31408 ${DCP_STATIC} 31408
${IPWAN} 31409 ${DCP_STATIC} 31409
EOF

    # 禁用UFW防火墙（如果存在）或配置允许端口
    echo "配置UFW防火墙（如果存在）..."
    if command -v ufw &> /dev/null; then
        # 如果系统有UFW，配置它允许所需端口
        ufw allow 443/tcp
        ufw allow 992/tcp
        ufw allow 5555/tcp
        ufw allow 500/udp
        ufw allow 4500/udp
        ufw allow 1701/udp
        # 允许Pi-Node节点端口
        for port in $(seq 31400 31409); do
            ufw allow $port/tcp
        done
        # 如果UFW处于活动状态，重新加载配置
        if ufw status | grep -q "active"; then
            ufw reload
        fi
    fi

    # 启动并设置开机自启动服务
    echo "开始启动并设置开机自启动服务..."
    systemctl daemon-reload
    systemctl enable vpnserver
    systemctl start vpnserver

    # 等待VPN服务器完全启动
    echo "等待VPN服务器完全启动..."
    sleep 10

    # 启动rinetd服务并检查状态
    echo "开始启动rinetd服务并检查状态..."
    systemctl restart rinetd
    sleep 2
    if ! systemctl is-active --quiet rinetd; then
        echo "错误：rinetd服务启动失败"
        systemctl status rinetd
        exit 1
    fi
    
    # 验证端口转发配置
    echo "验证端口转发配置..."
    # 检查rinetd配置是否正确加载
    if ! grep -q "31409" /etc/rinetd.conf; then
        echo "错误：rinetd配置文件中未找到端口31409的配置"
        cat /etc/rinetd.conf
        exit 1
    fi
    
    # 检查端口是否已开放
    for port in $(seq 31400 31409); do
        if ! iptables -L -n | grep -q "dpt:$port"; then
            echo "警告：端口 $port 可能未在防火墙中开放"
            # 尝试再次添加规则
            iptables -A INPUT -p tcp --dport $port -j ACCEPT
        fi
    done
    
    # 再次保存防火墙规则
    netfilter-persistent save

    # 配置rinetd服务开机自启动
    echo "开始配置rinetd服务开机自启动..."
    systemctl enable --now rinetd

    # 验证HUB是否创建成功
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始验证HUB是否创建成功..."
    if ! ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD Hub ${HUB}; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误：HUB创建失败，请检查以下配置："
        echo "- HUB名称: ${HUB}"
        echo "- 服务器密码: ${SERVER_PASSWORD}"
        echo "- VPN服务器状态: $(systemctl is-active vpnserver)"
        exit 1
    fi

    # 验证服务状态
    echo "验证服务状态..."
    for service in vpnserver rinetd; do
        if ! systemctl is-active --quiet $service; then
            echo "错误：$service 服务启动失败"
            systemctl status $service
            exit 1
        fi
    done
    
    # 单独检查dnsmasq服务，但不中断脚本执行
    if ! systemctl is-active --quiet dnsmasq; then
        echo "警告：dnsmasq 服务未启动，但不影响VPN核心功能"
        echo "如需DHCP功能，请手动检查dnsmasq配置并重启服务"
        systemctl status dnsmasq
    else
        echo "dnsmasq服务运行正常"
    fi
    
    # 测试端口转发
    echo "测试端口转发..."
    # 安装测试工具
    DEBIAN_FRONTEND=noninteractive apt install -y curl netcat-openbsd
    
    # 测试rinetd端口转发
    echo "检查rinetd端口转发状态..."
    if ! netstat -tulpn | grep rinetd | grep -q "31409"; then
        echo "警告：rinetd似乎没有监听31409端口"
        echo "尝试重启rinetd服务..."
        systemctl restart rinetd
        sleep 3
    fi
    
    # 检查公网端口是否可访问
    echo "检查公网端口是否可访问..."
    # 从内部测试端口转发
    if command -v nc &> /dev/null; then
        for port in $(seq 31400 31409); do
            if nc -z -v -w5 ${IPWAN} $port 2>&1 | grep -q "succeeded"; then
                echo "端口 $port 转发测试成功"
            else
                echo "警告：端口 $port 转发测试失败，可能需要检查防火墙或ISP限制"
            fi
        done
    fi

    echo ">>> +++ SoftEther VPN安装完成 +++！"
    echo "——————————————————————————————————————————————————————"
    echo "公网IP地址：$IPWAN"
    echo "客户端用户：$USER"
    echo "客户端密码：$SERVER_PASSWORD"
    echo "共享密码为：$SHARED_KEY"
    echo "HUB名称为：$HUB"
    echo "服务端端口：443、5555"
    echo "映射端口为：31400-31409"
    echo "映射地址为：$DCP_STATIC"
    
    # 添加端口转发故障排查指南
    echo "\n端口转发故障排查指南："
    echo "1. 如果外部无法访问端口(如 http://${IPWAN}:31409/)，请检查："
    echo "   - 确认rinetd服务正在运行: systemctl status rinetd"
    echo "   - 检查防火墙是否允许端口: iptables -L -n | grep 31409"
    echo "   - 检查端口是否在监听: netstat -tulpn | grep 31409"
    echo "   - 检查云服务商是否限制了这些端口"
    echo "   - 尝试重启rinetd服务: systemctl restart rinetd"
    echo "2. 如需手动添加端口转发规则，请编辑: /etc/rinetd.conf"
    echo "3. 如需手动开放防火墙端口: iptables -A INPUT -p tcp --dport 端口号 -j ACCEPT"
    echo "\n服务端管理工具下载：https://www.softether-download.com/files/softether/v4.42-9798-rtm-2023.06.30-tree/Windows/SoftEther_VPN_Server_and_VPN_Bridge/softether-vpnserver_vpnbridge-v4.42-9798-rtm-2023.06.30-windows-x86_x64-intel.exe"
    echo "客户端连接工具下载：https://www.softether-download.com/files/softether/v4.42-9798-rtm-2023.06.30-tree/Windows/SoftEther_VPN_Client/softether-vpnclient-v4.42-9798-rtm-2023.06.30-windows-x86_x64-intel.exe"
    echo "——————————————————————————————————————————————————————"
}

# 主菜单函数
MainMenu() {
    clear
    echo "================================================================"
    echo "====SoftEther VPN 一键安装脚本(Ubuntu专用)  微信：15521188891====="
    echo "================================================================"
    echo "1. 安装 VPN"
    echo "2. 卸载 VPN"
    echo "3. 退出"
    echo ""
    read -p "请输入选择 [1-3]: " choice

    case $choice in
        1)
            DSetup
            InstallVPN
            ;;
        2)
            DSetup
            Uninstall
            ;;
        3)
            exit 0
            ;;
        *)
            echo "无效选择，请重新输入"
            sleep 2
            MainMenu
            ;;
    esac
}

# 检查参数
if [ "$1" == "--uninstall" ] || [ "$1" == "-u" ]; then
    Uninstall
fi

# 调用主菜单
MainMenu