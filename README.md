🚀 vps-proxy: VPS 智能中转网关一键脚本vps-proxy 是一款专为 Linux VPS 设计的自动化网络管理工具。它通过极简的交互界面，帮助用户快速配置订阅节点、管理核心服务，并优化服务器性能。🌟 核心特性全自动化部署：通过 curl 一键安装，无需手动修改复杂的 config.yaml 或 json 文件。订阅流支持：直接通过菜单（选项 5）导入节点订阅地址，自动解析并更新。Web 可视化管理：内置 Web 面板安装（选项 7），支持在浏览器端切换节点、查看实时流量及延迟。系统级优化：一键开启 BBR 加速及 Swap 虚拟内存，确保在高并发中转场景下的稳定性。轻量高效：核心服务内存占用低，支持查看实时运行日志。🛠️ 功能模块模块功能说明核心管理服务的启停、重启及实时日志监测，快速排查连接问题。配置同步核心功能，支持批量导入订阅链接，自动生成路由配置。高级工具整合 BBR 加速、虚拟内存扩容、Geo 数据库（地理位置/绕路规则）更新。系统维护提供重置及彻底卸载功能，不留任何系统垃圾。💡 最佳实践：黄金搭档建议配合仓库 xsb-onekey 一起使用：xsb-onekey：用于在落地机（Server）端一键搭建高效的协议环境（如 Hysteria2, Sing-box, Xray 等）。vps-proxy：用于在中转机（Relay）端运行。将 xsb-onekey 生成的订阅或节点链接填入 vps-proxy，实现“中转 -> 落地”的完美链路。📥 安装与使用在你的 VPS 终端执行以下命令即可进入交互菜单：Bashbash <(curl -sL https://raw.githubusercontent.com/sockc/vps-proxy/main/install.sh)
⚠️ 注意事项权限需求：请确保以 root 用户运行。环境要求：建议使用 Ubuntu 20.04+ 或 Debian 11+ 系统。防火墙：如果安装了 Web 面板，请记得在 VPS 服务商的控制台开启相应的端口（脚本通常会提示）。
  
  
  
  
  🚀 VPS 智能网关


适合用于中转机，支持订阅地址

建议配合本仓库脚本使用
https://github.com/sockc/xsb-onekey

```bash
bash <(curl -sL https://raw.githubusercontent.com/sockc/vps-proxy/main/install.sh)
```
```bash
wget -O /usr/bin/vps-proxy https://raw.githubusercontent.com/sockc/vps-proxy/main/scripts/menu.sh
chmod +x /usr/bin/vps-proxy
vps-proxy
