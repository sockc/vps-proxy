#!/bin/bash

# =================配置区=================
GITHUB_USER="vinchi008"
REPO_NAME="vps-proxy"
BRANCH="main"
# ========================================

BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH"
INSTALL_DIR="/etc/myproxy"

# 1. 检查 Root 权限
if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 权限运行！"
    exit 1
fi

# 2. 安装必要依赖
echo "正在安装依赖..."
apt update -y
apt install -y wget curl unzip gzip tar

# 3. 创建目录
mkdir -p $INSTALL_DIR
mkdir -p $INSTALL_DIR/sub

# 4. 下载 Mihomo 内核 (自动判断架构)
ARCH=$(uname -m)
echo "检测系统架构: $ARCH"
if [[ $ARCH == "x86_64" ]]; then
    DL_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.17.0/mihomo-linux-amd64-v1.17.0.gz"
elif [[ $ARCH == "aarch64" ]]; then
    DL_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.17.0/mihomo-linux-arm64-v1.17.0.gz"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

if [ ! -f "$INSTALL_DIR/mihomo" ]; then
    echo "正在下载 Mihomo 内核..."
    wget -O "$INSTALL_DIR/mihomo.gz" "$DL_URL"
    gunzip -f "$INSTALL_DIR/mihomo.gz"
    chmod +x "$INSTALL_DIR/mihomo"
else
    echo "内核已存在，跳过下载。"
fi

# 5. 下载配置文件和脚本
echo "正在下载脚本和配置模板..."
# 如果已有配置，则不覆盖，防止误操作；如需重置请在菜单里选重置
if [ ! -f "$INSTALL_DIR/config.yaml" ]; then
    wget -O "$INSTALL_DIR/config.yaml" "$BASE_URL/config/template.yaml"
fi

# 【关键步骤】下载主程序到 /usr/bin/vps-proxy 实现快捷命令
wget -O "/usr/bin/vps-proxy" "$BASE_URL/scripts/menu.sh"
chmod +x "/usr/bin/vps-proxy"

# 6. 配置 Systemd 服务
cat > /etc/systemd/system/myproxy.service <<EOF
[Unit]
Description=Mihomo VPS Proxy
After=network.target

[Service]
Type=simple
User=root
# 启动前开启防火墙
ExecStartPre=/usr/bin/vps-proxy start_tproxy
# 启动内核 (-d 指定运行目录)
ExecStart=$INSTALL_DIR/mihomo -d $INSTALL_DIR
# 停止后清理防火墙
ExecStopPost=/usr/bin/vps-proxy stop_tproxy
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable myproxy

# 7. 下载 Geo 数据库
echo "初始化 Geo 数据库..."
wget -q -O "$INSTALL_DIR/geoip.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
wget -q -O "$INSTALL_DIR/geosite.dat" "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"

echo "================================="
echo "  ✅ 安装完成！"
echo "  👉 以后直接输入 vps-proxy 即可打开菜单"
echo "================================="

# 自动运行一次菜单
vps-proxy
