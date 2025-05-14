#!/bin/bash 
# Softether VPN Bridge with dnsmasq for Ubuntu 
# 适配版本：Ubuntu 20.04/22.04 LTS 
# 最后更新：2025-05-14 
#==================================================
 
# 密码验证函数 
DSetupA(){
    clear 
    echo "==================================================" 
    echo "====Softether一键安装脚本  微信：WX51529502=====" 
    echo "==================================================" 
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
    echo "==================================================" 
    echo "====Softether一键安装脚本  微信：15521188891=====" 
    echo "==================================================" 
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
 
#================================================== 
# 配置参数 
DCP_URL="https://raw.githubusercontent.com/ampetervip/DSoftEtherVip/main" 
LOCAL_IP="10.8.0.1"
LOCAL_RANGE="10.8.0.2,10.8.0.2"
DCP_DNS="8.8.8.8"
DCP_STATIC="10.8.0.2"
 
# 自动获取公网IP 
IPWAN=$(curl -s ifconfig.io) 
SERVER_IP=$IPWAN 
SERVER_PASSWORD="xiaojie"
SHARED_KEY="xiaojie"
USER="pi"
 
# 核心变量 
HUB="PiNodeHub"
HUB_PASSWORD=${SERVER_PASSWORD}
USER_PASSWORD=${SERVER_PASSWORD}
TARGET="/usr/local/"
 
# 安装前准备 
echo "+++ 开始安装SoftEther VPN +++"
apt-get update 
apt-get install -y wget dnsmasq expect build-essential libreadline-dev libssl-dev libncurses-dev iptables-persistent netfilter-persistent 
 
# 安装SoftEther 
wget ${DCP_URL}/softether-vpnserver-v4.38-9760-rtm-2021.08.17-linux-x64-64bit.tar.gz  
tar xzvf softether-vpnserver-v4.38-9760-rtm-2021.08.17-linux-x64-64bit.tar.gz  -C $TARGET 
rm -rf softether-vpnserver-v4.38-9760-rtm-2021.08.17-linux-x64-64bit.tar.gz  
cd ${TARGET}vpnserver 
make i_read_and_agree_the_license_agreement 
 
# 权限设置 
find ${TARGET}vpnserver -type f -print0 | xargs -0 chmod 600 
chmod 700 ${TARGET}vpnserver/vpnserver ${TARGET}vpnserver/vpncmd 
 
# 网络配置 
echo "net.ipv4.ip_forward  = 1" >>/etc/sysctl.conf  
sysctl -p 
 
# 服务管理文件（Ubuntu使用systemd）
cat > /etc/systemd/system/vpnserver.service  <<EOF 
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
 
# 初始化VPN配置 
systemctl daemon-reload 
systemctl start vpnserver 
${TARGET}vpnserver/vpncmd localhost /SERVER /CMD ServerPasswordSet ${SERVER_PASSWORD}
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD HubCreate ${HUB} /PASSWORD:${HUB_PASSWORD}
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD UserCreate ${USER} /GROUP:none /REALNAME:none /NOTE:none 
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD UserPasswordSet ${USER} /PASSWORD:${USER_PASSWORD}
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD IPsecEnable /L2TP:yes /L2TPRAW:yes /ETHERIP:yes /PSK:${SHARED_KEY} /DEFAULTHUB:${HUB}
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD BridgeCreate ${HUB} /DEVICE:soft /TAP:yes 
 
# 防火墙规则 
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE 
netfilter-persistent save 
 
# DNSMASQ配置 
cat > /etc/dnsmasq.conf  <<EOF 
interface=tap_soft 
dhcp-range=tap_soft,${LOCAL_RANGE},12h 
dhcp-option=option:netmask,255.255.255.0 
dhcp-option=tap_soft,3,${LOCAL_IP}
port=0 
dhcp-option=option:dns-server,${DCP_DNS}
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
cat > /etc/rinetd.conf  <<EOF 
0.0.0.0 31400 10.8.0.2 31400 
0.0.0.0 31401 10.8.0.2 31401 
0.0.0.0 31402 10.8.0.2 31402 
0.0.0.0 31403 10.8.0.2 31403 
0.0.0.0 31404 10.8.0.2 31404 
0.0.0.0 31405 10.8.0.2 31405 
0.0.0.0 31406 10.8.0.2 31406 
0.0.0.0 31407 10.8.0.2 31407 
0.0.0.0 31408 10.8.0.2 31408 
0.0.0.0 31409 10.8.0.2 31409 
0.0.0.0 825 10.8.0.2 825 
EOF 
 
# 启动服务 
systemctl restart dnsmasq 
systemctl enable vpnserver 
systemctl restart vpnserver 
systemctl enable rinetd 
systemctl restart rinetd 
 
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
