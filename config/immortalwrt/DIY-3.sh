#!/bin/bash

#================================================================================================
# 脚本：DIY-3-Auto-Detect-V3.sh (逻辑修正的最终版)
# 目标：
#   - [V3 核心修正] 准确地基于“上游网关”而非“本机IP”来确定上游网络，以应对复杂路由环境。
#   - 无需手动配置，移动到新网络后可自动适应。
#   - 使用 hotplug 脚本动态更新防火墙，健壮且可靠。
#   - 修复所有已知问题（拼写、依赖等）。
#================================================================================================

echo "--- 正在执行 DIY-3: 配置全自动 WAN 访问 LuCI (V3 - 最终版) ---"

# 1. 基础配置：仅启用 luci, 确保 jsonfilter 存在
# ====================================================================
sed -i '/CONFIG_PACKAGE_luci-/d' .config
echo "CONFIG_PACKAGE_luci=y" >> .config
sed -i '/CONFIG_PACKAGE_ubus/a CONFIG_PACKAGE_jsonfilter=y' .config
echo "✅ 已配置为仅使用 luci (HTTP) 并包含 jsonfilter"


# 2. uci-defaults 脚本：首次启动时创建占位符规则 (无变化)
# ====================================================================
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/98-setup-wan-firewall <<'EOF'
#!/bin/sh
uci set firewall.allow_wan_luci=rule
uci set firewall.allow_wan_luci.name='Allow-LuCI-From-Upstream-LAN'
uci set firewall.allow_wan_luci.src='wan'
uci set firewall.allow_wan_luci.proto='tcp'
uci set firewall.allow_wan_luci.dest_port='80'
uci set firewall.allow_wan_luci.target='ACCEPT'
uci set firewall.allow_wan_luci.enabled='0'
uci set uhttpd.main.rfc1918_filter='0'
uci commit firewall
uci commit uhttpd
exit 0
EOF
echo "✅ 已创建 uci-defaults 脚本"


# 3. hotplug 脚本：使用网关和掩码进行精确网络检测
# ====================================================================
mkdir -p files/etc/hotplug.d/iface
cat > files/etc/hotplug.d/iface/99-autodetect-wan-rule <<'EOF'
#!/bin/sh

# 只在 'wan' 接口 'ifup' 事件时执行
[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "wan" ] || exit 0

# 延时以确保路由和 ubus 信息完全就绪
sleep 2

# [V3 核心修正]
# 1. 从默认路由中获取权威的上游网关 IP
GATEWAY=$(ip route show default | awk '/default via/ {print $3; exit}')

# 2. 从 ubus 获取权威的子网掩码位数
WAN_INFO=$(ubus call network.interface.wan status)
MASK=$(echo "$WAN_INFO" | jsonfilter -e '@["ipv4-address"][0].mask')

# 必须同时成功获取到网关和子网掩码
if [ -n "$GATEWAY" ] && [ -n "$MASK" ]; then
    # 组合成 网关IP/掩码位数 的CIDR格式 (e.g., 192.168.1.1/24)
    # 防火墙后端(iptables/nftables)足够智能，能将此正确解释为整个源网络 192.168.1.0/24
    UPSTREAM_CIDR="$GATEWAY/$MASK"
    
    uci set firewall.allow_wan_luci.src_ip="$UPSTREAM_CIDR"
    uci set firewall.allow_wan_luci.enabled='1'
    uci commit firewall

    logger -t wan-firewall "检测到上游网关为 $GATEWAY，子网掩码为 /$MASK。已基于 $UPSTREAM_CIDR 开启 WAN 口 LuCI 访问。"
    /etc/init.d/firewall reload
else
    # 任何一个信息获取失败，都保持规则禁用，安全第一
    uci set firewall.allow_wan_luci.enabled='0'
    uci commit firewall
    logger -t wan-firewall "无法确定上游网关或子网掩码。WAN 口 LuCI 访问保持禁用。"
    /etc/init.d/firewall reload
fi
EOF
echo "✅ 已创建 hotplug 脚本，使用网关进行精确网络检测"


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
