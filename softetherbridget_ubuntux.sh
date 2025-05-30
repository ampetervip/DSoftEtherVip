#!/bin/bash
# Softether VPN Bridge for Ubuntu 24.04
# 作者：DengCaiPing
# 微信：51529502
# 时间：2025-05-15
# 版本：v1.1

# 系统环境变量
# IPWAN=$(curl -4 ifconfig.io)  # 设置为固定公网IP
IPWAN=$(ip -4 addr show eth0 | grep -oP 'inet \K[\d.]+') # 获取eth0网卡IP地址
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
    local valid_passwords=("515900" "223300")  # 允许的密码列表
    read -p "请输入密码：" PASSWD
    
    # 检查输入是否在允许的密码列表中
    local is_valid=0
    for password in "${valid_passwords[@]}"; do
        if [ "$PASSWD" == "$password" ]; then
            is_valid=1
            break
        fi
    done
    
    if [ $is_valid -eq 1 ]; then
        :  # 密码正确，执行后续操作
    else
        echo "密码错误，请重新输入！"
        DSetup  # 递归调用重新输入
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
    DEBIAN_FRONTEND=noninteractive apt install -y build-essential wget expect zlib1g-dev libssl-dev net-tools rinetd

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
    
    # 生成随机MAC地址函数
    generate_random_mac() {
        # 生成随机MAC地址，确保第一个字节的第二位为0（保证是单播地址）
        local mac=""
        # 第一个字节，确保是02开头（本地管理的单播地址）
        local first_byte=$(printf "%02x" $((0x02 + (RANDOM % 0xFE) & 0xFE)))
        mac="${first_byte}"
        
        # 生成剩余5个字节
        for i in {1..5}; do
            local byte=$(printf "%02x" $((RANDOM % 256)))
            mac="${mac}:${byte}"
        done
        
        echo "$mac"
    }
    
    # 生成随机MAC地址
    RANDOM_MAC=$(generate_random_mac)
    echo "生成的随机MAC地址: ${RANDOM_MAC}"
    
    # 配置SecureNAT以确保固定IP分配
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD SecureNatEnable
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD SecureNatHostSet /MAC:${RANDOM_MAC} /IP:${LOCAL_IP} /MASK:255.255.255.0
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD DhcpSet /START:${DHCP_MIN} /END:${DHCP_MAX} /MASK:255.255.255.0 /EXPIRE:7200 /GW:${LOCAL_IP} /DNS:${DCP_DNS} /DNS2:8.8.4.4 /DOMAIN:local /LOG:yes
    
    # 配置tap_soft接口
    ip addr add ${LOCAL_IP}/24 dev tap_soft
    ip link set tap_soft up

    # 配置网络转发规则和IPv4优先级
    iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
    netfilter-persistent save
    systemctl restart netfilter-persistent

    # 验证并配置tap_soft接口
    echo "验证并配置tap_soft接口..."
    if ! ip link show tap_soft > /dev/null 2>&1; then
        echo "错误：tap_soft接口未创建成功"
        exit 1
    fi
    
    # 确保tap_soft接口配置正确
    ip addr flush dev tap_soft
    ip addr add ${LOCAL_IP}/24 dev tap_soft
    ip link set tap_soft up

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
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD SetMaxSession 100000
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD SetMaxConnection 100000
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD SetMaxBufferSize 4294967295
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD SetHubMaxSession ${HUB} 50000
    ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD SetHubMaxConnection ${HUB} 50000

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

    clear
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
    echo "服务端管理工具下载：https://www.softether-download.com/files/softether/v4.42-9798-rtm-2023.06.30-tree/Windows/SoftEther_VPN_Server_and_VPN_Bridge/softether-vpnserver_vpnbridge-v4.42-9798-rtm-2023.06.30-windows-x86_x64-intel.exe"
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
