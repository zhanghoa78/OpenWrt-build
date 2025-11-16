# -----------------------------------------------------------------
# 警告：以下代码将在固件中开启WAN口管理，这是极不安全的！
# 仅用于你知道后果的特殊编译。
# -----------------------------------------------------------------

# 确保 uci-defaults 目录存在
mkdir -p files/etc/uci-defaults

# 写入 uci-defaults 脚本 (99-enable-wan-admin)
cat > files/etc/uci-defaults/99-enable-wan-admin << 'EOF'
#!/bin/sh

# -----------------------------------------------------------------
# 路由器首次启动时将执行此脚本
# -----------------------------------------------------------------

# 开启 WAN 口的 SSH (22 端口) - 极度危险！
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-SSH-WAN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='22'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'

# 开启 WAN 口的 LuCI (HTTP - 80 端口) - 极不安全！
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-LuCI-WAN-HTTP'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='80'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'

# (可选) 开启 WAN 口的 LuCI (HTTPS - 443 端口)
# uci add firewall rule
# uci set firewall.@rule[-1].name='Allow-LuCI-WAN-HTTPS'
# uci set firewall.@rule[-1].src='wan'
# uci set firewall.@rule[-1].dest_port='443'
# uci set firewall.@rule[-1].proto='tcp'
# uci set firewall.@rule[-1].target='ACCEPT'

# 提交所有更改
uci commit firewall

# 重新加载防火墙以应用规则
/etc/init.d/firewall reload

exit 0
EOF

echo "已在 files/etc/uci-defaults/ 中添加 99-enable-wan-admin 脚本"
# -----------------------------------------------------------------
# WAN口管理设置完毕
# -----------------------------------------------------------------
