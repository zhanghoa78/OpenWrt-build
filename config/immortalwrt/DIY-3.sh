#!/bin/bash

#================================================================================================
# 脚本：DIY-3-Auto-Detect-V3.sh (精简融合版)
# 目标：
#   - 不创建任何初始化规则
#   - 仅当 WAN 接口上线且网络可识别时，动态创建完整 LuCI 访问规则
#   - 使用 V3 精确逻辑（网关 + 掩码）
#   - 无 jsonfilter 依赖，自动安全加固
#================================================================================================

echo "--- 正在执行 DIY-3: 仅通过 hotplug 动态添加 WAN LuCI 规则（V3 精简版）---"

# 1. 启用 LuCI（必须）
grep -v "CONFIG_PACKAGE_luci-" .config > .config.tmp && mv .config.tmp .config
echo "CONFIG_PACKAGE_luci=y" >> .config
echo "✅ 已启用 LuCI"

# 2. 【关键】不再创建 uci-defaults 脚本！规则完全由 hotplug 动态生成

# 3. 创建 hotplug 脚本：检测 + 创建规则 + 安全加固
# ====================================================================
mkdir -p files/etc/hotplug.d/iface
cat > files/etc/hotplug.d/iface/99-autodetect-wan-rule <<'EOF'
#!/bin/sh

# 仅处理 WAN 类接口的 ifup 事件
[ "$ACTION" = "ifup" ] || exit 0
case "$INTERFACE" in
    wan|wan0|internet) : ;;
    *) exit 0 ;;
esac

sleep 2

# === 1. 获取网关和设备 ===
GATEWAY=$(ip route show default 2>/dev/null | awk '/default via/ {print $3; exit}')
DEV=$(ip route show default 2>/dev/null | awk '/default via/ {print $5; exit}')

if [ -z "$GATEWAY" ] || [ -z "$DEV" ]; then
    logger -t wan-firewall "WAN 未就绪，跳过配置。"
    exit 1
fi

CIDR=$(ip addr show "$DEV" 2>/dev/null | awk '/inet / && !/127.0.0.1/ {print $2; exit}')
if [ -z "$CIDR" ]; then
    logger -t wan-firewall "WAN 无 IPv4 地址，跳过配置。"
    exit 1
fi

MASK=${CIDR#*/}
UPSTREAM_CIDR="$GATEWAY/$MASK"

# === 2. 安全加固：确保 WAN zone 的 input 是 REJECT ===
for i in $(seq 0 10); do
    if uci get firewall.@zone[$i].name 2>/dev/null | grep -q "^wan$"; then
        # 仅当当前是 ACCEPT 时才改为 REJECT（避免反复写入）
        current=$(uci get firewall.@zone[$i].input 2>/dev/null)
        if [ "$current" != "REJECT" ]; then
            uci set firewall.@zone[$i].input='REJECT'
            uci commit firewall
            /etc/init.d/firewall reload >/dev/null 2>&1
        fi
        break
    fi
done

# === 3. 动态创建完整规则（覆盖可能存在的旧规则）===
uci -q delete firewall.allow_wan_luci
uci set firewall.allow_wan_luci=rule
uci set firewall.allow_wan_luci.name='Allow-LuCI-From-Upstream-LAN'
uci set firewall.allow_wan_luci.src='wan'
uci set firewall.allow_wan_luci.src_ip="$UPSTREAM_CIDR"
uci set firewall.allow_wan_luci.proto='tcp'
uci set firewall.allow_wan_luci.dest_port='80'
uci set firewall.allow_wan_luci.target='ACCEPT'

# 配置 uHTTPd 允许私有 IP 请求（只需设一次，但重复设无害）
uci set uhttpd.main.rfc1918_filter='0'

uci commit firewall
uci commit uhttpd
/etc/init.d/firewall reload >/dev/null 2>&1
/etc/init.d/uhttpd reload >/dev/null 2>&1

logger -t wan-firewall "✅ 成功创建 WAN LuCI 规则：允许 $UPSTREAM_CIDR 访问"
EOF
chmod +x files/etc/hotplug.d/iface/99-autodetect-wan-rule
echo "✅ 已创建 hotplug 脚本（动态创建规则，无初始化）"


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
