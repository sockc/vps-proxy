#!/bin/bash

# ================= 颜色与配置 =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

WORKDIR="/etc/myproxy"
CONFIG_FILE="$WORKDIR/config.yaml"

# ================= 辅助函数 =================

# 获取服务状态
check_status() {
    if systemctl is-active --quiet myproxy; then
        STATUS="${GREEN}🟢 运行中${PLAIN}"
        # 获取 PID 和 内存占用 (RSS)
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

# 获取面板信息
get_panel_info() {
    # 提取端口 (去除空格和引号)
    UI_PORT=$(grep "^external-controller" $CONFIG_FILE | awk -F: '{print $2}' | tr -d ' "')
    # 提取密钥
    UI_SECRET=$(grep "^secret" $CONFIG_FILE | awk -F: '{print $2}' | tr -d ' "')
    # 获取公网IP
    PUBLIC_IP=$(curl -s4m 2 https://api.ip.sb/ip || echo "你的IP")
    
    if [ -z "$UI_PORT" ]; then UI_PORT="9090"; fi
    if [ -z "$UI_SECRET" ]; then UI_SECRET="未知"; fi
}

# ================= 核心功能函数 =================

# ... (原有的 set_subscribe, install_ui, start_tproxy 等函数保留不动) ...
# 为了篇幅，我这里只列出新增和修改的函数，请把之前的 install_ui, set_subscribe 等贴在这里
# 或者确保你现有的功能函数还在，不要删掉了

# [新增] 修改面板密码
function change_secret() {
    echo -e "\n=== 修改 Web 面板密钥 ==="
    read -p "请输入新的密码 (不输入则取消): " NEW_SECRET
    if [ -z "$NEW_SECRET" ]; then return; fi
    
    # 修改配置文件
    sed -i "s/^secret:.*/secret: \"$NEW_SECRET\"/" "$CONFIG_FILE"
    
    echo -e "✅ 密码已修改为: ${GREEN}$NEW_SECRET${PLAIN}"
    echo "正在重启服务以应用更改..."
    systemctl restart myproxy
    echo "重启完成。"
}

# [原功能] 这里建议保留你之前的 set_subscribe, install_ui, enable_bbr, manage_swap 等所有函数
# 务必把它们复制过来放到这里！

# ================= 主菜单 UI =================
function show_menu() {
    check_status
    get_panel_info
    
    clear
    echo -e "==============================================================="
    echo -e "   🚀 ${SKYBLUE}VPS 智能网关脚本 (Mihomo Core)${PLAIN} | ${YELLOW}v1.1.0 增强版${PLAIN}"
    echo -e "==============================================================="
    echo -e " 服务状态: ${STATUS}     内存占用: ${YELLOW}${MEM}${PLAIN}"
    echo -e "==============================================================="
    
    echo -e " ${GREEN}[ 核心管理 ]${PLAIN}"
    echo -e "  1. 启动服务            2. 停止服务"
    echo -e "  3. 重启服务            4. 查看实时日志"
    
    echo -e "\n ${GREEN}[ 订阅与配置 ]${PLAIN}"
    echo -e "  5. 设置/更新订阅链接   ${YELLOW}<-- [核心]${PLAIN}"
    echo -e "  6. 修改面板密码        ${SKYBLUE}<-- [新增]${PLAIN}"
    
    echo -e "\n ${GREEN}[ 面板与工具 ]${PLAIN}"
    echo -e "  7. 安装 Web 面板       ${YELLOW}<-- [推荐]${PLAIN}"
    echo -e "  8. 开启 BBR 加速       9. 虚拟内存 (Swap)"
    echo -e " 10. 更新 Geo 数据库"
    
    echo -e "\n  0. 退出脚本"
    echo -e "==============================================================="
    
    # 底部面板信息区
    if [[ "$STATUS" == *"${GREEN}"* ]]; then
        echo -e " 📡 ${SKYBLUE}Web 面板地址:${PLAIN} http://${PUBLIC_IP}:${UI_PORT}/ui"
        echo -e " 🔑 ${SKYBLUE}API 访问密钥:${PLAIN} ${GREEN}${UI_SECRET}${PLAIN}"
    else
        echo -e " ⚠️ 服务未启动，暂无面板信息。"
    fi
    echo -e "==============================================================="
    
    read -p " 请输入选项: " num
    
    case "$num" in
        1) systemctl start myproxy; echo -e "${GREEN}已启动${PLAIN}";;
        2) systemctl stop myproxy; echo -e "${RED}已停止${PLAIN}";;
        3) systemctl restart myproxy; echo -e "${GREEN}已重启${PLAIN}";;
        4) journalctl -u myproxy -f ;;
        5) set_subscribe ;;
        6) change_secret ;;
        7) install_ui ;;
        8) enable_bbr ;;
        9) manage_swap ;;
        10) update_geo ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效输入${PLAIN}" ;;
    esac
    
    if [ "$num" != "0" ] && [ "$num" != "4" ]; then
        echo -e "\n按回车键返回主菜单..."
        read
        show_menu
    fi
}

# 入口判断 (保留)
if [ "$1" == "start_tproxy" ]; then
    # ... (保留之前的防火墙逻辑) ...
    # ⚠️ 注意：这里必须把你原来的 start_tproxy 函数逻辑放进去，否则systemd调用会报错
    # 为了完整性，你需要把你之前的 iptables 逻辑复制到这里
    : 
elif [ "$1" == "stop_tproxy" ]; then
    # ... (保留之前的防火墙逻辑) ...
    :
else
    show_menu
fi
