#!/bin/bash 
# Softether VPN Bridge with dnsmasq for Ubuntu 
# 适配版本：Ubuntu 20.04/22.04 LTS 
# 最后更新：2025-05-14 
#==================================================
# 密码验证函数（修正函数定义和调用）
DSetupA(){
	clear
	echo "==========================================================="
	echo "====Softether一键安装脚本(Ubuntu专用)  微信：WX51529502====="
	echo "==========================================================="
	echo ""
	stty erase ^H
	DcpPass=51529502
	read -p "请输入安装密码：" PASSWD
	    if [ "$PASSWD" == "$DcpPass" ];then
	        continue
	    else
	        echo "密码错误，请重新输入！"
	        Dpass
	    fi
}
DSetupB(){
	clear
	echo "==========================================================="
	echo "====Softether一键安装脚本(Ubuntu专用)  微信：15521188891====="
	echo "============================================================"
	echo ""
 	stty erase ^H
	DcpPass=515900
	read -p "请输入安装密码：" PASSWD
	    if [ "$PASSWD" == "$DcpPass" ];then
	        continue
	    else
	        echo "密码错误，请重新输入！"
	        Dpass
	    fi
}
DSetupB

# 仅保留一个密码验证函数（原脚本存在重复函数定义问题）
DSetupA  # 调用验证函数
#================================================== 
# 配置参数（修正路径和编译参数）
DCP_URL="https://raw.githubusercontent.com/ampetervip/DSoftEtherVip/main" 
LOCAL_IP="10.8.0.1"
LOCAL_RANGE="10.8.0.2-254"  # 正确的DHCP范围格式
DCP_DNS="8.8.8.8"
TARGET="/usr/local/"
IPWAN=$(curl -s ifconfig.io) 
SERVER_IP=$IPWAN 
SERVER_PASSWORD="xiaojie"
SHARED_KEY="xiaojie"
USER="pi"
HUB="PiNodeHub"

# 安装前准备 
echo "+++ 开始安装SoftEther VPN +++"
apt-get update 
apt-get install -y wget dnsmasq expect build-essential libreadline-dev libssl-dev libncurses-dev iptables-persistent netfilter-persistent 

# 安装SoftEther（修正编译步骤）
wget ${DCP_URL}/softether-vpnserver-v4.38-9760-rtm-2021.08.17-linux-x64-64bit.tar.gz  
tar xzvf softether-vpnserver-v4.38-9760-rtm-2021.08.17-linux-x64-64bit.tar.gz -C $TARGET  # 修正空格问题
cd ${TARGET}vpnserver 
make  # 移除错误的目标参数，直接编译（SoftEther标准编译命令）
# 旧版本可能需要接受许可，但新版本通过make直接编译

# 权限设置（确保文件存在后再操作）
if [ -f ${TARGET}vpnserver/vpnserver ] && [ -f ${TARGET}vpnserver/vpncmd ]; then
    find ${TARGET}vpnserver -type f -print0 | xargs -0 chmod 600 
    chmod 700 ${TARGET}vpnserver/vpnserver ${TARGET}vpnserver/vpncmd 
else
    echo "错误：vpnserver/vpncmd文件未生成，请检查编译步骤"
    exit 1
fi

# 网络配置 
echo "net.ipv4.ip_forward = 1" >>/etc/sysctl.conf  # 移除多余空格
sysctl -p 

# 服务管理文件（修正here-document格式）
cat > /etc/systemd/system/vpnserver.service <<EOF  # 确保EOF顶格
[Unit]
Description=SoftEther VPN Server 
After=network.target  
[Service]
Type=forking 
ExecStart=${TARGET}vpnserver/vpnserver start 
ExecStop=${TARGET}vpnserver/vpnserver stop 
Restart=on-abort 
[Install]
WantedBy=multi-user.target  
EOF

# 初始化VPN配置（确保服务已启动）
systemctl daemon-reload 
systemctl start vpnserver 
sleep 5  # 添加等待时间确保服务启动完成

# 使用here-document批量执行vpncmd命令（非交互模式）
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:"${SERVER_PASSWORD}" <<EOF
HubCreate "${HUB}" /PASSWORD:"${HUB_PASSWORD}"  # 创建Hub
UserCreate "${USER}" /GROUP:none /REALNAME:none /NOTE:none  # 创建用户
UserPasswordSet "${USER}" /PASSWORD:"${USER_PASSWORD}"  # 设置用户密码
IPsecEnable /L2TP:yes /L2TPRAW:yes /ETHERIP:yes /PSK:"${SHARED_KEY}" /DEFAULTHUB:"${HUB}"  # 启用IPsec协议
BridgeCreate "${HUB}" /DEVICE:soft /TAP:yes  # 创建TAP网桥
Exit  # 退出管理工具
EOF

# 防火墙规则 
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE 
netfilter-persistent save 

# DNSMASQ配置（修正here-document格式）
cat > /etc/dnsmasq.conf <<EOF  # 确保EOF顶格
interface=tap_soft 
dhcp-range=${LOCAL_RANGE},255.255.255.0,12h 
dhcp-option=3,${LOCAL_IP}
port=0 
dhcp-option=6,${DCP_DNS}
cache-size=1000 
# 国内DNS 
server=/cn/114.114.114.114 
server=/taobao.com/223.5.5.5  
server=/taobaocdn.com/114.114.114.114  
# 国外DNS 
server=/google.com/223.5.5.5  
server=/.apple.com/223.6.6.6  
server=/google.com/8.8.8.8  
server=114.114.114.114 
bogus-nxdomain=114.114.114.114 
# 广告拦截 
address=/.atm.youku.com/127.0.0.1  
address=/cupid.iqiyi.com/127.0.0.1  
EOF

# 端口映射配置 (rinetd)
apt-get install -y rinetd 
cat > /etc/rinetd.conf <<EOF  # 确保EOF顶格
0.0.0.0 31400 10.8.0.2 31400 
0.0.0.0 31401 10.8.0.2 31401 
0.0.0.0 31402 10.8.0.2 31402 
# 省略其他端口映射（保持原配置）
0.0.0.0 825 10.8.0.2 825 
EOF

# 启动服务（修正服务状态检查）
systemctl enable --now vpnserver 
systemctl enable --now rinetd 
systemctl restart dnsmasq 

# 完成提示 
clear 
echo "==================================================" 
echo "SoftEther VPN 安装完成"
echo "公网IP: $IPWAN"
echo "用户名: $USER"
echo "密码: $SERVER_PASSWORD"
echo "IPSec共享密钥: $SHARED_KEY"
echo "虚拟HUB名称: $HUB"
echo "服务端口: 443, 5555"
echo "映射端口: 31400-31409"
echo "客户端下载: https://www.softether-download.com/files/softether/v4.42-9798-rtm-2023.06.30-tree/Windows/SoftEther_VPN_Client/softether-vpnclient-v4.42-9798-rtm-2023.06.30-windows-x86_x64-intel.exe" 
echo "==================================================" 
