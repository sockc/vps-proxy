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
    echo -e "\n=== 设置/删除 机场订阅 ==="
    
    # 读取当前链接（用于显示）
    CURRENT_URL=$(grep "# \[SUBLINK\]" "$CONFIG_FILE" | awk -F'"' '{print $2}')
    if [[ "$CURRENT_URL" == "INSERT_LINK_HERE" ]]; then
        echo -e "当前状态: ${YELLOW}未设置${PLAIN}"
    else
        echo -e "当前订阅: ${GREEN}${CURRENT_URL:0:30}...${PLAIN}" # 只显示前30字符
    fi

    echo -e "\n操作指南:"
    echo -e "1. 输入新链接 -> 覆盖设置"
    echo -e "2. 输入 ${RED}clear${PLAIN}  -> 删除订阅"
    echo -e "3. 直接回车   -> 取消操作"
    
    read -p "请输入: " USER_LINK

    # 逻辑 1: 取消
    if [ -z "$USER_LINK" ]; then 
        echo "已取消。"; return
    fi

    # 逻辑 2: 删除 (恢复为占位符)
    if [ "$USER_LINK" == "clear" ]; then
        echo "正在清除订阅..."
        # 恢复为初始占位符，保留 # [SUBLINK] 标记以便下次修改
        sed -i "s|.*# \[SUBLINK\]|    url: \"INSERT_LINK_HERE\" # [SUBLINK]|" "$CONFIG_FILE"
        echo "✅ 订阅已删除（恢复初始状态）。"
        systemctl restart myproxy
        return
    fi

    # 逻辑 3: 更新
    # 简单的格式检查
    if [[ "$USER_LINK" != http* ]]; then
        echo "⚠️ 警告: 链接必须以 http 或 https 开头！"
        return
    fi

    echo "正在写入新订阅..."
    sed -i "s|.*# \[SUBLINK\]|    url: \"$USER_LINK\" # [SUBLINK]|" "$CONFIG_FILE"
    
    echo "✅ 订阅已更新！正在重启服务..."
    systemctl restart myproxy
    echo "服务已重启。"
}

# ================= 升级版：面板切换中心 =================
function install_ui() {
    echo -e "\n=== 选择 Web 控制面板 ==="
    echo -e " 1. ${GREEN}Metacubexd${PLAIN} (原版，功能最全)"
    echo -e " 2. ${SKYBLUE}Zashboard${PLAIN}  (你图片里的那个，UI更好看)"
    echo -e " 3. ${YELLOW}Yacd${PLAIN}        (经典旧版，轻量简洁)"
    echo -e "========================="
    read -p " 请选择 [1-3] (默认2): " choice
    
    case "$choice" in
        1)
            # Metacubexd 官方版
            URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
            DIR_PATTERN="metacubexd-gh-pages"
            MSG="Metacubexd"
            ;;
        3)
            # Yacd (Yacd-meta)
            URL="https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip"
            DIR_PATTERN="Yacd-meta-gh-pages"
            MSG="Yacd"
            ;;
        *)
            # Zashboard (默认推荐)
            URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
            DIR_PATTERN="zashboard-gh-pages"
            MSG="Zashboard"
            ;;
    esac

    echo -e "\n⬇️  正在下载 ${MSG}..."
    
    # 清理旧文件
    rm -rf "$WORKDIR/ui"
    mkdir -p "$WORKDIR/ui"
    rm -rf /tmp/ui_extract
    mkdir -p /tmp/ui_extract

    # 下载
    wget -q -O /tmp/ui.zip "$URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 下载失败！请检查网络或 GitHub 连接。${PLAIN}"
        return
    fi

    # 解压并安装
    echo "📦 正在解压安装..."
    unzip -q /tmp/ui.zip -d /tmp/ui_extract
    
    # 智能移动文件 (因为解压后的文件夹名字可能带版本号，所以用通配符)
    # 逻辑：移动解压目录下的第一个文件夹里的所有内容到 ui 目录
    mv /tmp/ui_extract/*/* "$WORKDIR/ui/"

    # 清理垃圾
    rm -rf /tmp/ui.zip /tmp/ui_extract
    
    echo -e "✅ ${GREEN}${MSG} 面板已安装！${PLAIN}"
    echo -e "👉 请在浏览器中 ${YELLOW}强制刷新 (Ctrl+F5)${PLAIN} 即可看到新界面。"
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
    # --- 红眼猫 Dashboard (整合状态显示) ---
    echo -e "\033[1;34m =======================================\033[0m"
    # 第一行：显示脚本名称 (黄色高亮)
    echo -e "\033[1;37m      |\__/,|   (\`\ \033[0m    \033[1;33mVPS 智能网关\033[0m"
    # 第二行：显示运行状态 (继承 STATUS 变量原本的颜色)
    echo -e "\033[1;37m    _.|\033[1;31mo o\033[1;37m  |_   ) ) \033[0m   状态: ${STATUS}"
    # 第三行：显示内存使用 (绿色高亮，呼应绿色的爪子线条)
    echo -e "\033[1;32m  -(((---(((-------- \033[0m   \033[1;32m内存: ${MEM}\033[0m"
    echo -e "\033[1;34m =======================================\033[0m"
    
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
    
    # 底部状态信息栏
    if [[ "$STATUS" == *"${GREEN}"* ]]; then
        echo -e " 📡 面板地址: http://${PUBLIC_IP}:${UI_PORT}/ui"
        echo -e " 🔑 访问密钥: ${GREEN}${UI_SECRET}${PLAIN}"
    fi

    # 订阅状态检查
    SUB_CHECK=$(grep "# \[SUBLINK\]" "$CONFIG_FILE" | grep "INSERT_LINK_HERE")
    if [ -z "$SUB_CHECK" ]; then
        echo -e " 🔗 订阅状态: ${GREEN}已配置${PLAIN}"
    else
        echo -e " 🔗 订阅状态: ${YELLOW}未配置 (请执行步骤 5)${PLAIN}"
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
