#!/bin/bash
# Softether VPN Bridge for Ubuntu 24.04
# 作者：DengCaiPing
# 微信：51529502
# 时间：2025-05-15
# 版本：v1.0
#==================================================
# 密码验证函数
DSetup() {
    clear 
    echo "==========================================================="
    echo "====Softether一键安装脚本(Ubuntu专用)  微信：15521188891====="
    echo "============================================================"
    echo ""
    stty erase ^H 
    local DcpPass=515900  # 添加local声明
    read -p "请输入安装密码：" PASSWD 
    if [ "$PASSWD" == "$DcpPass" ]; then 
        :  # 空操作
    else 
        echo "密码错误，请重新输入！"
        DSetupB  # 递归调用自身
    fi
}

# 调用验证函数
DSetup
#==================================================
# 系统环境变量
IPWAN=$(curl -4 ifconfig.io)
SERVER_IP=$IPWAN
USER="pi"
SERVER_PASSWORD="xiaojie"
SHARED_KEY="xiaojie"
HUB="PiNodeHub"
HUB_PASSWORD=${SERVER_PASSWORD}
USER_PASSWORD=${SERVER_PASSWORD}
TARGET="/usr/local/"

# 网络配置
LOCAL_IP="10.0.8.1"
DCP_DNS="8.8.8.8"
DCP_STATIC="10.0.8.2"
# 确保DHCP只分配固定IP
DHCP_MIN="10.0.8.2"
DHCP_MAX="10.0.8.2"

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
DEBIAN_FRONTEND=noninteractive apt install -y build-essential wget expect zlib1g-dev libssl-dev

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

# 配置VPN服务器
echo "开始配置VPN服务器..."
# 设置服务器密码并验证
${TARGET}vpnserver/vpncmd localhost /SERVER /CMD ServerPasswordSet ${SERVER_PASSWORD}
# 验证密码设置是否成功
if ! ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD About; then
    echo "错误：服务器密码设置失败，请检查密码"
    exit 1
fi
# 创建HUB并验证
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD HubCreate ${HUB} /PASSWORD:${HUB_PASSWORD}
# 验证HUB创建是否成功
if ! ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD Hub ${HUB}; then
    echo "错误：HUB创建失败，请检查密码"
    exit 1
fi
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD UserCreate ${USER} /GROUP:none /REALNAME:none /NOTE:none
# 设置用户密码并验证
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD UserPasswordSet ${USER} /PASSWORD:${USER_PASSWORD}
# 验证用户密码设置是否成功
if ! ${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD User ${USER}; then
    echo "错误：用户密码设置失败，请检查密码"
    exit 1
fi
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD IPsecEnable /L2TP:yes /L2TPRAW:yes /ETHERIP:yes /PSK:${SHARED_KEY} /DEFAULTHUB:${HUB}
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD BridgeCreate ${HUB} /DEVICE:soft /TAP:yes

# 配置SecureNAT和DHCP设置
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD SecureNatEnable
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD SecureNatHostSet /IP:${LOCAL_IP} /MASK:255.255.255.0
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD DhcpSet /START:${DHCP_MIN} /END:${DHCP_MAX} /MASK:255.255.255.0 /EXPIRE:7200 /GW:${LOCAL_IP} /DNS:${DCP_DNS} /DNS2:8.8.4.4 /DOMAIN:local /LOG:yes

# 配置网络转发规则和IPv4优先级
echo "开始配置网络转发规则和IPv4优先级..."
echo "precedence ::ffff:0:0/96 100" >> /etc/gai.conf
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
iptables -A FORWARD -i tap_soft -j ACCEPT
iptables -A FORWARD -o tap_soft -j ACCEPT
netfilter-persistent save

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
0.0.0.0 31400 ${DCP_STATIC} 31400
0.0.0.0 31401 ${DCP_STATIC} 31401
0.0.0.0 31402 ${DCP_STATIC} 31402
0.0.0.0 31403 ${DCP_STATIC} 31403
0.0.0.0 31404 ${DCP_STATIC} 31404
0.0.0.0 31405 ${DCP_STATIC} 31405
0.0.0.0 31406 ${DCP_STATIC} 31406
0.0.0.0 31407 ${DCP_STATIC} 31407
0.0.0.0 31408 ${DCP_STATIC} 31408
0.0.0.0 31409 ${DCP_STATIC} 31409
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

# 添加iptables规则允许端口转发
echo "开始添加iptables规则允许端口转发..."
for port in {31400..31409}; do
    iptables -A INPUT -p tcp --dport $port -j ACCEPT
    iptables -A FORWARD -p tcp --dport $port -j ACCEPT
done
netfilter-persistent save


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
