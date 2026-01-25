#!/bin/bash

# ================= 颜色与配置 =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

WORKDIR="/etc/myproxy"
CONFIG_FILE="$WORKDIR/config.yaml"
# 请确保这里是你自己的 GitHub 仓库地址
TEMPLATE_URL="https://raw.githubusercontent.com/vinchi008/vps-proxy/main/config/template.yaml"

# ================= 状态检测函数 =================

# 获取服务状态
check_status() {
    if systemctl is-active --quiet myproxy; then
        STATUS="${GREEN}🟢 运行中${PLAIN}"
        PID=$(pgrep -f "mihomo -d" | head -n 1)
        if [ -n "$PID" ]; then
            MEM=$(ps -o rss= -p "$PID" | awk '{print int($1/1024)"MB"}')
        else
            MEM="未知"
        fi
    else
        STATUS="${RED}🔴 已停止${PLAIN}"
        MEM="0MB"
    fi
}

# [核心修复] 获取面板信息 - 增强版
get_panel_info() {
    # 1. 提取 external-controller 这一行，并去除所有引号
    LINE=$(grep "^external-controller" "$CONFIG_FILE" | tr -d '"' | tr -d "'")
    
    # 2. 使用 awk 提取最后一个冒号后面的内容，并只保留数字
    # 逻辑：以冒号分隔，取最后一个字段($NF)，然后用 grep 提取纯数字
    UI_PORT=$(echo "$LINE" | awk -F: '{print $NF}' | grep -oE '[0-9]+')
    
    # 3. 提取密钥 (同样去除引号)
    UI_SECRET=$(grep "^secret" "$CONFIG_FILE" | awk -F: '{print $2}' | tr -d ' "' | tr -d "'")
    
    # 4. 获取 IP
    PUBLIC_IP=$(curl -s4m 2 https://api.ip.sb/ip || echo "你的IP")
    
    # 5. 兜底逻辑：如果提取失败或提取到了0.0.0.0，强制设为 9090
    if [ -z "$UI_PORT" ] || [ "$UI_PORT" == "0.0.0.0" ]; then 
        UI_PORT="9090"
    fi
    
    if [ -z "$UI_SECRET" ]; then UI_SECRET="未知"; fi
}

# ================= 核心功能：防火墙 (TProxy) =================
function start_tproxy() {
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1)
    
    iptables -t mangle -N MYPROXY
    # 直连保留地址
    iptables -t mangle -A MYPROXY -d 0.0.0.0/8 -j RETURN
    iptables -t mangle -A MYPROXY -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A MYPROXY -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A MYPROXY -d 169.254.0.0/16 -j RETURN
    iptables -t mangle -A MYPROXY -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A MYPROXY -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A MYPROXY -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A MYPROXY -d 240.0.0.0/4 -j RETURN
    
    # 转发 TCP/UDP
    iptables -t mangle -A MYPROXY -p tcp -j TPROXY --on-port 7893 --tproxy-mark 1
    iptables -t mangle -A MYPROXY -p udp -j TPROXY --on-port 7893 --tproxy-mark 1
    iptables -t mangle -A PREROUTING -j MYPROXY
    
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

# ================= 功能模块 =================

function set_subscribe() {
    echo -e "\n=== 设置机场订阅 ==="
    read -p "请输入订阅链接(http开头): " USER_LINK
    if [ -z "$USER_LINK" ]; then echo "❌ 输入为空"; return; fi
    
    sed -i "s|.*# \[SUBLINK\]|    url: \"$USER_LINK\" # [SUBLINK]|" "$CONFIG_FILE"
    
    echo "✅ 订阅已写入，正在重启服务..."
    systemctl restart myproxy
    echo "服务已重启。"
}

function install_ui() {
    echo "正在下载 Metacubexd 面板..."
    rm -rf "$WORKDIR/ui"
    mkdir -p "$WORKDIR/ui"
    wget -q -O /tmp/ui.zip "https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
    unzip -q /tmp/ui.zip -d /tmp/
    mv /tmp/metacubexd-gh-pages/* "$WORKDIR/ui/"
    rm -rf /tmp/ui.zip /tmp/metacubexd-gh-pages
    echo "✅ 面板安装成功！"
}

function change_secret() {
    echo -e "\n=== 修改 Web 面板密钥 ==="
    read -p "请输入新的密码 (不输入则取消): " NEW_SECRET
    if [ -z "$NEW_SECRET" ]; then return; fi
    sed -i "s/^secret:.*/secret: \"$NEW_SECRET\"/" "$CONFIG_FILE"
    echo -e "✅ 密码已修改，正在重启..."
    systemctl restart myproxy
}

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

function manage_swap() {
    echo -e "\n=== 虚拟内存管理 ==="
    echo "1. 开启 2GB Swap (推荐)"
    echo "2. 删除 Swap"
    read -p "选择: " s
    if [ "$s" == "1" ]; then
        if [ -f /swapfile ]; then echo "已存在"; return; fi
        fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo "vm.swappiness=20" >> /etc/sysctl.conf
        echo "✅ Swap 已开启"
    elif [ "$s" == "2" ]; then
        swapoff /swapfile 2>/dev/null
        rm -f /swapfile
        sed -i '/\/swapfile/d' /etc/fstab
        echo "✅ Swap 已删除"
    fi
}

function reset_config() {
    echo -e "\n${RED}⚠️  警告：所有配置将被重置为初始状态！${PLAIN}"
    read -p "确认吗？[y/n]: " c
    if [[ "$c" != "y" ]]; then return; fi
    
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    wget -O "$CONFIG_FILE" "$TEMPLATE_URL"
    if [ $? -eq 0 ]; then
        echo "✅ 重置成功，正在重启..."
        systemctl restart myproxy
        echo "请重新设置订阅。"
    else
        echo "❌ 下载模板失败，已恢复备份。"
        mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
    fi
}

function uninstall_script() {
    echo -e "\n${RED}⚠️  严重警告：将彻底删除本脚本及服务！${PLAIN}"
    read -p "确认吗？[y/n]: " c
    if [[ "$c" != "y" ]]; then return; fi
    
    systemctl stop myproxy
    systemctl disable myproxy
    rm -f /etc/systemd/system/myproxy.service
    systemctl daemon-reload
    rm -rf "$WORKDIR"
    rm -f /usr/bin/vps-proxy
    echo "✅ 卸载完成。再见！"
    exit 0
}

# ================= 主菜单 =================
function show_menu() {
    check_status
    get_panel_info
    
    clear
    echo -e "==============================================================="
    echo -e "   🚀 ${SKYBLUE}VPS 智能网关脚本${PLAIN} | ${YELLOW}vps-proxy${PLAIN}"
    echo -e "==============================================================="
    echo -e " 状态: ${STATUS}   内存: ${YELLOW}${MEM}${PLAIN}"
    echo -e "==============================================================="
    
    echo -e " ${GREEN}[ 核心 ]${PLAIN}"
    echo -e "  1. 启动服务            2. 停止服务"
    echo -e "  3. 重启服务            4. 查看日志"
    
    echo -e "\n ${GREEN}[ 配置 ]${PLAIN}"
    echo -e "  5. 设置订阅链接        6. 修改面板密码"
    
    echo -e "\n ${GREEN}[ 工具 ]${PLAIN}"
    echo -e "  7. 安装 Web 面板       8. 开启 BBR 加速"
    echo -e "  9. 虚拟内存 (Swap)    10. 更新 Geo 数据库"
    
    echo -e "\n ${GREEN}[ 维护 ]${PLAIN}"
    echo -e " 11. 重置配置文件       12. ${RED}彻底卸载脚本${PLAIN}"
    echo -e "\n  0. 退出"
    echo -e "==============================================================="
    
    if [[ "$STATUS" == *"${GREEN}"* ]]; then
        echo -e " 📡 面板地址: http://${PUBLIC_IP}:${UI_PORT}/ui"
        echo -e " 🔑 访问密钥: ${GREEN}${UI_SECRET}${PLAIN}"
    fi
    echo -e "==============================================================="
    
    read -p " 选择: " num
    
    case "$num" in
        1) systemctl start myproxy; echo "已启动";;
        2) systemctl stop myproxy; echo "已停止";;
        3) systemctl restart myproxy; echo "已重启";;
        4) journalctl -u myproxy -f ;;
        5) set_subscribe ;;
        6) change_secret ;;
        7) install_ui ;;
        8) enable_bbr ;;
        9) manage_swap ;;
        10) update_geo ;;
        11) reset_config ;;
        12) uninstall_script ;;
        0) exit 0 ;;
        *) echo "无效输入" ;;
    esac
    
    if [ "$num" != "0" ] && [ "$num" != "4" ] && [ "$num" != "12" ]; then
        echo -e "\n按回车返回..."
        read
        show_menu
    fi
}

# 入口判断
if [ "$1" == "start_tproxy" ]; then
    start_tproxy
    exit 0
elif [ "$1" == "stop_tproxy" ]; then
    stop_tproxy
    exit 0
else
    show_menu
fi
