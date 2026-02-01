#!/bin/bash

# ================= 颜色与配置 =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

WORKDIR="/etc/myproxy"
CONFIG_FILE="$WORKDIR/config.yaml"

# =========== 核心配置区 (请修改这里) ===========
# 1. 完整版规则地址 (默认)
TEMPLATE_FULL="https://raw.githubusercontent.com/vinchi008/vps-proxy/main/config/template.yaml"

# 2. 轻量版规则地址 (请填入你的 URL)
# ⚠️ 注意：轻量版 yaml 文件中，订阅位置必须包含 # [SUBLINK] 标记，否则无法自动写入订阅
TEMPLATE_LIGHT="https://raw.githubusercontent.com/vinchi008/vps-proxy/main/config/template_light.yaml" 

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
    LINE=$(grep "^external-controller" "$CONFIG_FILE" | tr -d '"' | tr -d "'")
    UI_PORT=$(echo "$LINE" | awk -F: '{print $NF}' | grep -oE '[0-9]+')
    UI_SECRET=$(grep "^secret" "$CONFIG_FILE" | awk -F: '{print $2}' | tr -d ' "' | tr -d "'")
    PUBLIC_IP=$(curl -s4m 2 https://api.ip.sb/ip || echo "你的IP")
    
    if [ -z "$UI_PORT" ] || [ "$UI_PORT" == "0.0.0.0" ]; then 
        UI_PORT="9090"
    fi
    if [ -z "$UI_SECRET" ]; then UI_SECRET="未知"; fi
}

# ================= 核心功能：防火墙 (TProxy) =================
# ⚠️ 这里的逻辑非常重要，已完整保留
function start_tproxy() {
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n1)
    
    iptables -t mangle -N MYPROXY
    iptables -t mangle -A MYPROXY -d 0.0.0.0/8 -j RETURN
    iptables -t mangle -A MYPROXY -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A MYPROXY -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A MYPROXY -d 169.254.0.0/16 -j RETURN
    iptables -t mangle -A MYPROXY -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A MYPROXY -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A MYPROXY -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A MYPROXY -d 240.0.0.0/4 -j RETURN
    
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
    CURRENT_URL=$(grep "# \[SUBLINK\]" "$CONFIG_FILE" | awk -F'"' '{print $2}')
    if [[ "$CURRENT_URL" == "INSERT_LINK_HERE" ]]; then
        echo -e "当前状态: ${YELLOW}未设置${PLAIN}"
    else
        echo -e "当前订阅: ${GREEN}${CURRENT_URL:0:30}...${PLAIN}"
    fi

    echo -e "\n操作指南:"
    echo -e "1. 输入新链接 -> 覆盖设置"
    echo -e "2. 输入 ${RED}clear${PLAIN}  -> 删除订阅"
    echo -e "3. 直接回车   -> 取消操作"
    read -p "输入订阅链接: " USER_LINK

    if [ -z "$USER_LINK" ]; then echo "已取消。"; return; fi

    if [ "$USER_LINK" == "clear" ]; then
        echo "正在清除订阅..."
        sed -i "s|.*# \[SUBLINK\]|    url: \"INSERT_LINK_HERE\" # [SUBLINK]|" "$CONFIG_FILE"
        echo "✅ 订阅已删除。"
        systemctl restart myproxy
        return
    fi

    if [[ "$USER_LINK" != http* ]]; then
        echo "⚠️ 警告: 链接必须以 http 或 https 开头！"
        return
    fi

    echo "正在写入..."
    sed -i "s|.*# \[SUBLINK\]|    url: \"$USER_LINK\" # [SUBLINK]|" "$CONFIG_FILE"
    echo "✅ 订阅已更新！正在重启..."
    systemctl restart myproxy
}

# === 新增：分流规则切换中心 ===
function switch_template() {
    echo -e "\n=== 切换分流规则模板 ==="
    echo -e "当前选择可能会覆盖 config.yaml，但脚本会尝试保留你的订阅链接和密码。"
    echo -e "------------------------------------------------"
    echo -e " 1. ${GREEN}完整版规则${PLAIN} (包含详细分流，推荐性能强机器)"
    echo -e " 2. ${YELLOW}轻量版规则${PLAIN} (精简规则，适合小内存机器)"
    echo -e "------------------------------------------------"
    read -p "请选择 [1-2]: " t_choice

    case "$t_choice" in
        1)
            TARGET_URL="$TEMPLATE_FULL"
            NAME="完整版"
            ;;
        2)
            TARGET_URL="$TEMPLATE_LIGHT"
            NAME="轻量版"
            ;;
        *)
            echo "已取消"
            return
            ;;
    esac

    echo -e "\n🔄 正在准备切换至 [${NAME}]..."

    # 1. 备份当前重要信息
    echo "👉 正在提取当前订阅和密钥..."
    # 提取订阅链接 (提取引号中的内容)
    OLD_SUB=$(grep "# \[SUBLINK\]" "$CONFIG_FILE" | awk -F'"' '{print $2}')
    # 提取密钥
    OLD_SECRET=$(grep "^secret" "$CONFIG_FILE" | awk -F: '{print $2}' | tr -d ' "' | tr -d "'")

    # 2. 下载新模板
    echo "⬇️  正在下载新配置文件..."
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak_switch" # 临时备份以防下载失败
    wget -q -O "$CONFIG_FILE" "$TARGET_URL"

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 下载失败！请检查 URL 是否正确。已恢复原配置。${PLAIN}"
        mv "${CONFIG_FILE}.bak_switch" "$CONFIG_FILE"
        return
    fi

    # 3. 还原信息
    echo "✍️  正在还原个人配置..."
    
    # 还原订阅
    if [[ -n "$OLD_SUB" ]] && [[ "$OLD_SUB" != "INSERT_LINK_HERE" ]]; then
        # 寻找新文件中的占位符并替换
        sed -i "s|.*# \[SUBLINK\]|    url: \"$OLD_SUB\" # [SUBLINK]|" "$CONFIG_FILE"
        echo "   - 订阅链接已还原"
    else
        echo "   - 原配置无订阅，保持默认"
    fi

    # 还原密码
    if [[ -n "$OLD_SECRET" ]]; then
        sed -i "s/^secret:.*/secret: \"$OLD_SECRET\"/" "$CONFIG_FILE"
        echo "   - 面板密钥已还原"
    fi

    # 4. 重启
    echo "✅ 切换成功！正在重启服务..."
    systemctl restart myproxy
    echo "🎉 当前运行模式：${NAME}"
}

function install_ui() {
    echo -e "\n=== Web 控制面板管理 ==="
    echo -e " 1. 安装/切换 ${GREEN}Metacubexd${PLAIN}"
    echo -e " 2. 安装/切换 ${SKYBLUE}Zashboard${PLAIN}"
    echo -e " 3. 安装/切换 ${YELLOW}Yacd${PLAIN}"
    echo -e " 4. ${RED}卸载当前面板${PLAIN}"
    echo -e "========================="
    read -p " 请选择 [1-4] (默认2): " choice
    
    if [ "$choice" == "4" ]; then
        rm -rf "$WORKDIR/ui"
        echo "✅ 面板已卸载。"
        return
    fi

    case "$choice" in
        1) URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip";;
        3) URL="https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip";;
        *) URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip";;
    esac

    echo -e "\n⬇️  正在安装..."
    rm -rf "$WORKDIR/ui"
    mkdir -p "$WORKDIR/ui"
    rm -rf /tmp/ui_extract
    mkdir -p /tmp/ui_extract
    wget -q -O /tmp/ui.zip "$URL"
    unzip -q /tmp/ui.zip -d /tmp/ui_extract
    mv /tmp/ui_extract/*/* "$WORKDIR/ui/"
    rm -rf /tmp/ui.zip /tmp/ui_extract
    echo -e "✅ 安装完成！请 Ctrl+F5 刷新浏览器。"
}

function change_secret() {
    read -p "请输入新的密码: " NEW_SECRET
    if [ -z "$NEW_SECRET" ]; then return; fi
    sed -i "s/^secret:.*/secret: \"$NEW_SECRET\"/" "$CONFIG_FILE"
    systemctl restart myproxy
    echo "✅ 密码已修改。"
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
    echo "1. 开启 2GB Swap"
    echo "2. 删除 Swap"
    read -p "选择: " s
    if [ "$s" == "1" ]; then
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
    echo -e "\n${RED}⚠️  警告：重置将丢失所有配置（订阅/密码）！${PLAIN}"
    read -p "确认吗？[y/n]: " c
    if [[ "$c" != "y" ]]; then return; fi
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    wget -O "$CONFIG_FILE" "$TEMPLATE_FULL"
    systemctl restart myproxy
    echo "✅ 已重置为【完整版】初始状态。"
}

function create_shortcut() {
    SCRIPT_PATH=$(readlink -f "$0")
    ln -sf "$SCRIPT_PATH" /usr/bin/vp
    chmod +x "$SCRIPT_PATH"
    echo -e "✅ 快捷指令 'vp' 创建成功！"
}

function uninstall_script() {
    read -p "确认彻底卸载吗？[y/n]: " c
    if [[ "$c" != "y" ]]; then return; fi
    rm -f /usr/bin/vp
    systemctl stop myproxy
    systemctl disable myproxy
    rm -f /etc/systemd/system/myproxy.service
    systemctl daemon-reload
    rm -rf "$WORKDIR"
    echo "✅ 卸载完成。"
    exit 0
}

# ================= 主菜单 =================
function show_menu() {
    check_status
    get_panel_info
    
    clear
    echo -e "\033[1;34m =======================================\033[0m"
    echo -e "\033[1;37m     |\__/,|   (\`\ \033[0m    \033[1;33mVPS 智能网关\033[0m"
    echo -e "\033[1;37m   _.|\033[1;31mo o\033[1;37m  |_   ) ) \033[0m    状态: ${STATUS}"
    echo -e "\033[1;32m  -(((---(((-------- \033[0m    \033[1;32m内存: ${MEM}\033[0m"
    echo -e "\033[1;34m =======================================\033[0m"
    
    echo -e " ${GREEN}[ 核心 ]${PLAIN}"
    echo -e "  1. 启动服务            2. 停止服务"
    echo -e "  3. 重启服务            4. 查看日志"
    
    echo -e "\n ${GREEN}[ 配置 ]${PLAIN}"
    echo -e "  5. 设置订阅链接        6. 修改面板密码"
    echo -e "  7. ${YELLOW}切换分流规则${PLAIN} (完整/轻量)"
    
    echo -e "\n ${GREEN}[ 工具 ]${PLAIN}"
    echo -e "  8. 管理 Web 面板       9. 开启 BBR 加速"
    echo -e " 10. 虚拟内存 (Swap)    11. 更新 Geo 数据库"
    echo -e " 12. 创建快捷指令 (vp)"
    
    echo -e "\n ${GREEN}[ 维护 ]${PLAIN}"
    echo -e " 13. 重置配置文件       14. ${RED}彻底卸载脚本${PLAIN}"
    echo -e "\n  0. 退出"
    echo -e "============================================"
    
    if [[ "$STATUS" == *"${GREEN}"* ]]; then
        if [ -d "$WORKDIR/ui" ]; then
            echo -e " 📡 面板: http://${PUBLIC_IP}:${UI_PORT}/ui"
        else
            echo -e " 📡 面板: ${YELLOW}未安装${PLAIN}"
        fi
        echo -e " 🔑 密钥: ${GREEN}${UI_SECRET}${PLAIN}"
    fi

    SUB_CHECK=$(grep "# \[SUBLINK\]" "$CONFIG_FILE" | grep "INSERT_LINK_HERE")
    if [ -z "$SUB_CHECK" ]; then
        echo -e " 🔗 订阅: ${GREEN}已配置${PLAIN}"
    else
        echo -e " 🔗 订阅: ${YELLOW}未配置${PLAIN}"
    fi
    echo -e "============================================"
    
    read -p " 选择: " num
    
    case "$num" in
        1) systemctl start myproxy; echo "已启动";;
        2) systemctl stop myproxy; echo "已停止";;
        3) systemctl restart myproxy; echo "已重启";;
        4) journalctl -u myproxy -f ;;
        5) set_subscribe ;;
        6) change_secret ;;
        7) switch_template ;; # 新增的切换功能
        8) install_ui ;;
        9) enable_bbr ;;
        10) manage_swap ;;
        11) update_geo ;;
        12) create_shortcut ;;
        13) reset_config ;;
        14) uninstall_script ;;
        0) exit 0 ;;
        *) echo "无效输入" ;;
    esac
    
    if [ "$num" != "0" ] && [ "$num" != "4" ] && [ "$num" != "14" ]; then
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
