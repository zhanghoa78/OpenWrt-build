#!/bin/bash

#============================================================================================
# 脚本：diy-part2.sh
# 用途：1. 创建 uci-defaults 脚本 (开启WAN管理)
#       2. 修改源代码 (个性化参数)
#============================================================================================

# 1. 开启WAN口管理 (你刚刚提供的脚本)
#-------------------------------------------------------------------------------------------
# 警告：以下代码将在固件中开启WAN口管理，这是极不安全的！
echo "--- 正在执行 (diy-part2): 创建 99-enable-wan-admin 脚本 ---"

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

echo "--- 99-enable-wan-admin 脚本创建完毕 ---"
# -----------------------------------------------------------------
# WAN口管理设置完毕
# -----------------------------------------------------------------


# 2. 定制个性化参数 (来自你的脚本)
#-------------------------------------------------------------------------------------------
# 1-设置管理地址 (注意：源 IP 已从 192.168.6.1 改为 192.168.1.1)
# sed -i 's/192.168.1.1/192.168.2.223/g' package/base-files/files/bin/config_generate

# 2-编译内核版本 (已注释)
#sed -i 's/KERNEL_PATCHVER:=5.15/KERNEL_PATCHVER:=6.1/g' ./target/linux/mediatek/Makefile

# 3-添加固件日期 (已注释)
#sed -i 's/IMG_PREFIX:=/IMG_PREFIX:=$(BUILD_DATE_PREFIX)-/g' ./include/image.mk
#sed -i '/DTS_DIR:=$(LINUX_DIR)/a\BUILD_DATE_PREFIX := $(shell date +'%F')' ./include/image.mk

# 4-增固件连接数 (激活)
echo "--- 正在执行 (diy-part2): 增加固件连接数 ---"
sed -i '/customized in this file/a net.netfilter.nf_conntrack_max=165535' package/base-files/files/etc/sysctl.conf

echo "--- diy-part2.sh 脚本执行完毕 ---"
