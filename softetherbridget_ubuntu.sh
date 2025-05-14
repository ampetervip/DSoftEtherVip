#!/bin/bash
# Softether VPN Bridge with dnsmasq for Ubuntu
# References:
#==================================================
DSetupA(){
    clear
    echo "==========================================================="
    echo "====Softether一键安装脚本(Ubuntu专用)  微信：WX51529502====="
    echo "============================================================"
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
    echo "============================================================"
    echo "====Softether一键安装脚本(Ubuntu专用)   微信：15521188891====="
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

#==================================================
#设定文件服务器IP变量
DCP_URL="https://raw.githubusercontent.com/ampetervip/DSoftEtherVip/main"
#虚拟网卡本地IP
LOCAL_IP="10.8.0.1"
#虚拟网卡本地分配IP范围
LOCAL_RANGE="10.8.0.2,10.8.0.254"
#虚拟网卡本地分配DNS
DCP_DNS="8.8.8.8"
#客户端固定MAC
#DCP_MAC="5E:6E:83:46:F0:91"
#客户端固定IP
DCP_STATIC="10.8.0.2"
#==================================================


IPWAN=$(curl ifconfig.io)
SERVER_IP=$IPWAN
#VPN密码
SERVER_PASSWORD="xiaojie"
#IPSec共享密钥
SHARED_KEY="xiaojie"
USER="pi"

#可以输入使用退格
stty erase ^H
#read -n "输入服务器公网IP[$IPWAN]:"
#read SERVER_IP
#read -p "输入客户端网卡MAC地址(例:AA:BB:CC:DD:EE:FF): " DCP_MAC
#echo ""
#read -p "创建VPN用户名: " USER
#echo ""
#read  -p "创建VPN密码: " SERVER_PASSWORD
#echo ""
#read  -p "设置IPSec共享密钥: " SHARED_KEY
#echo ""
echo "+++ 现在坐下来，等待安装完成 +++"
HUB="PiNodeHub"
HUB_PASSWORD=${SERVER_PASSWORD}
USER_PASSWORD=${SERVER_PASSWORD}
TARGET="/usr/local/"

# 更新系统并安装依赖
apt-get update -y
apt-get install -y wget dnsmasq expect build-essential zlib1g-dev libssl-dev libreadline-dev libncurses-dev iptables-persistent

# 下载并安装Softether
wget ${DCP_URL}/softether-vpnserver-v4.38-9760-rtm-2021.08.17-linux-x64-64bit.tar.gz
tar xzvf softether-vpnserver-v4.38-9760-rtm-2021.08.17-linux-x64-64bit.tar.gz -C $TARGET
rm -rf softether-vpnserver-v4.38-9760-rtm-2021.08.17-linux-x64-64bit.tar.gz
cd ${TARGET}vpnserver
make
find ${TARGET}vpnserver -type f -print0 | xargs -0 chmod 600
chmod 700 ${TARGET}vpnserver/vpnserver ${TARGET}vpnserver/vpncmd

# 启用IP转发
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# 下载并配置Softether服务
wget -P /etc/init.d/ ${DCP_URL}/vpnserver_ubuntu
mv /etc/init.d/vpnserver_ubuntu /etc/init.d/vpnserver
sed -i "s/\[LOCAL_IP]/${LOCAL_IP}/g" /etc/init.d/vpnserver
chmod 755 /etc/init.d/vpnserver
update-rc.d vpnserver defaults
/etc/init.d/vpnserver start

# 配置Softether
${TARGET}vpnserver/vpncmd localhost /SERVER /CMD ServerPasswordSet ${SERVER_PASSWORD}
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD HubCreate ${HUB} /PASSWORD:${HUB_PASSWORD}
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD UserCreate ${USER} /GROUP:none /REALNAME:none /NOTE:none
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /HUB:${HUB} /CMD UserPasswordSet ${USER} /PASSWORD:${USER_PASSWORD}
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD IPsecEnable /L2TP:yes /L2TPRAW:yes /ETHERIP:yes /PSK:${SHARED_KEY} /DEFAULTHUB:${HUB}
${TARGET}vpnserver/vpncmd localhost /SERVER /PASSWORD:${SERVER_PASSWORD} /CMD BridgeCreate ${HUB} /DEVICE:soft /TAP:yes

# 流量转发配置
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
iptables-save > /etc/iptables/rules.v4

# 配置DNSMASQ
cat /dev/null > /etc/dnsmasq.conf
cat <<EOF >> /etc/dnsmasq.conf
#网卡接口名称
interface=tap_soft
#客户端分配IP段
dhcp-range=tap_soft,${LOCAL_RANGE},12h
#客户端分配子网掩码
dhcp-option=option:netmask,255.255.255.0
#客户端分配网关
dhcp-option=tap_soft,3,${LOCAL_IP}
port=0
#客户端分配DNS
dhcp-option=option:dns-server,${DCP_DNS}
#客户端分配固定IP
#dhcp-host=${DCP_MAC},${DCP_STATIC} 
#调整 DNS 缓存大小
cache-size=1000

#=================================
#国内指定DNS
server=/cn/114.114.114.114
server=/taobao.com/223.5.5.5
server=/taobaocdn.com/114.114.114.114
#国外指定DNS
server=/google.com/223.5.5.5
server=/.apple.com/223.6.6.6
server=/google.com/8.8.8.8

server=114.114.114.114
bogus-nxdomain=114.114.114.114
#=================================
#优酷广告拦截
address=/.atm.youku.com/127.0.0.1
#爱奇艺广告拦截
address=/cupid.iqiyi.com/127.0.0.1
#=================================
EOF

# PiNode端口映射安装
apt-get install -y rinetd
cat /dev/null > /etc/rinetd.conf
cat <<EOF >> /etc/rinetd.conf
# Pi-Node节点端口转发
0.0.0.0     31400     ${DCP_STATIC}      31400
0.0.0.0     31401     ${DCP_STATIC}      31401
0.0.0.0     31402     ${DCP_STATIC}      31402
0.0.0.0     31403     ${DCP_STATIC}      31403
0.0.0.0     31404     ${DCP_STATIC}      31404
0.0.0.0     31405     ${DCP_STATIC}      31405
0.0.0.0     31406     ${DCP_STATIC}      31406
0.0.0.0     31407     ${DCP_STATIC}      31407
0.0.0.0     31408     ${DCP_STATIC}      31408
0.0.0.0     31409     ${DCP_STATIC}      31409
EOF

# 启动服务
systemctl enable rinetd
systemctl restart rinetd
systemctl enable dnsmasq
systemctl restart dnsmasq
systemctl enable netfilter-persistent
systemctl restart netfilter-persistent

clear
echo  ">>> +++ SoftEther VPN安装完成 +++！"
echo "——————————————————————————————————————————————————————"
echo "--------SoftEther VPN安装完成！--------"
echo "公网IP地址：$IPWAN"
echo "客户端用户：$USER"
echo "客户端密码：$SERVER_PASSWORD"
echo "共享密码为：$SHARED_KEY"
echo "HUB名称为：$HUB"
echo "服务端端口：443、5555"
echo "映射端口为：31400-31409"
echo "映射地址为：$DCP_STATIC"
echo "服务端管理：https://www.softether-download.com/files/softether/v4.42-9798-rtm-2023.06.30-tree/Windows/SoftEther_VPN_Server_and_VPN_Bridge/softether-vpnserver_vpnbridge-v4.42-9798-rtm-2023.06.30-windows-x86_x64-intel.exe"
echo "客户端连接：https://www.softether-download.com/files/softether/v4.42-9798-rtm-2023.06.30-tree/Windows/SoftEther_VPN_Client/softether-vpnclient-v4.42-9798-rtm-2023.06.30-windows-x86_x64-intel.exe"
echo "——————————————————————————————————————————————————————"    
