#!/bin/bash

# 全局变量
WORKDIR="/etc/myproxy"
CONFIG_FILE="$WORKDIR/config.yaml"
CORE_BIN="$WORKDIR/mihomo"

# =======================
# 1. 核心功能：订阅设置
# =======================
function set_subscribe() {
    echo -e "\n=== 设置机场订阅 ==="
    read -p "请输入订阅链接(http开头): " USER_LINK
    if [ -z "$USER_LINK" ]; then echo "❌ 输入为空"; return; fi
    
    # 这里的 sed 使用 | 分隔，防止 url 中的 / 报错
    sed -i "s|.*# \[SUBLINK\]|    url: \"$USER_LINK\" # [SUBLINK]|" "$CONFIG_FILE"
    
    echo "✅ 订阅已写入，正在重启应用..."
    systemctl restart myproxy
    echo "服务已重启。"
}

# =======================
# 2. 核心功能：安装面板
# =======================
function install_ui() {
    echo "正在下载 Metacubexd 面板..."
    rm -rf "$WORKDIR/ui"
    mkdir -p "$WORKDIR/ui"
    wget -q -O /tmp/ui.zip "https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
    unzip -q /tmp/ui.zip -d /tmp/
    mv /tmp/metacubexd-gh-pages/* "$WORKDIR/ui/"
    rm -rf /tmp/ui.zip /tmp/metacubexd-gh-pages
    echo "✅ 面板安装成功！访问 http://IP:9090/ui 密码: 123456"
}

# =======================
# 3. 核心功能：TProxy 防火墙 (开关)
# =======================
function start_tproxy() {
    # 开启 IP 转发
    sysctl -w net.ipv4.ip_forward=1 > /dev/null

    # 获取默认网卡
    IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1)
    
    # 创建链
    iptables -t mangle -N MYPROXY
    # 直连局域网和保留地址
    iptables -t mangle -A MYPROXY -d 0.0.0.0/8 -j RETURN
    iptables -t mangle -A MYPROXY -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A MYPROXY -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A MYPROXY -d 169.254.0.0/16 -j RETURN
    iptables -t mangle -A MYPROXY -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A MYPROXY -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A MYPROXY -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A MYPROXY -d 240.0.0.0/4 -j RETURN
    
    # 将流量标记为 1 并重定向到 7893
    iptables -t mangle -A MYPROXY -p tcp -j TPROXY --on-port 7893 --tproxy-mark 1
    iptables -t mangle -A MYPROXY -p udp -j TPROXY --on-port 7893 --tproxy-mark 1
    iptables -t mangle -A PREROUTING -j MYPROXY
    
    # 策略路由
    ip rule add fwmark 1 table 100
    ip route add local 0.0.0.0/0 dev lo table 100
    echo "🔥 TProxy 防火墙规则已开启 (网卡: $IFACE)"
}

function stop_tproxy() {
    iptables -t mangle -D PREROUTING -j MYPROXY 2>/dev/null
    iptables -t mangle -F MYPROXY 2>/dev/null
    iptables -t mangle -X MYPROXY 2>/dev/null
    ip rule del fwmark 1 table 100 2>/dev/null
    ip route del local 0.0.0.0/0 dev lo table 100 2>/dev/null
    echo "🛑 TProxy 规则已清理"
}

# =======================
# 4. 运维工具
# =======================
function enable_bbr() {
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    echo "✅ BBR 已开启"
}

function update_geo() {
    echo "更新 Geo 数据库..."
    wget -O "$WORKDIR/geoip.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
    wget -O "$WORKDIR/geosite.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
    systemctl restart myproxy
    echo "✅ 更新完成"
}

# =======================
# 5. 主菜单 UI
# =======================
function show_menu() {
    clear
    echo "=================================="
    echo "   VPS 智能网关脚本 (Mihomo Core)"
    echo "=================================="
    echo " 1. 启动服务      2. 停止服务"
    echo " 3. 重启服务      4. 查看日志"
    echo "----------------------------------"
    echo " 5. 设置订阅链接  <-- [必做]"
    echo " 6. 安装Web面板   <-- [推荐]"
    echo "----------------------------------"
    echo " 7. 开启BBR加速   8. 更新Geo库"
    echo " 0. 退出"
    echo "=================================="
    read -p "选择: " num
    
    case "$num" in
        1) systemctl start myproxy; echo "已启动";;
        2) systemctl stop myproxy; echo "已停止";;
        3) systemctl restart myproxy; echo "已重启";;
        4) journalctl -u myproxy -f ;;
        5) set_subscribe ;;
        6) install_ui ;;
        7) enable_bbr ;;
        8) update_geo ;;
        0) exit 0 ;;
        *) echo "无效输入" ;;
    esac
    
    if [ "$num" != "0" ] && [ "$num" != "4" ]; then
        read -p "按回车返回..."
        show_menu
    fi
}

# 脚本入口判断
# 如果带参数 (比如由 systemd 调用)，则执行对应函数
if [ "$1" == "start_tproxy" ]; then
    start_tproxy
    exit 0
elif [ "$1" == "stop_tproxy" ]; then
    stop_tproxy
    exit 0
else
    # 没参数则显示菜单
    show_menu
fi
