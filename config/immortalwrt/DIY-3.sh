#!/bin/bash

#================================================================================================
# 脚本：DIY-3-Auto-Detect-V3.sh (SSH + LuCI 合并规则版)
#================================================================================================

echo "--- 正在执行 DIY-3: 动态添加 WAN 管理权限 (合并 80/22 端口) ---"

# 1. 启用 LuCI
grep -v "CONFIG_PACKAGE_luci-" .config > .config.tmp && mv .config.tmp .config
echo "CONFIG_PACKAGE_luci=y" >> .config
echo "✅ 已启用 LuCI"

# 2. 创建 hotplug 脚本
mkdir -p files/etc/hotplug.d/iface
cat > files/etc/hotplug.d/iface/99-autodetect-wan-rule <<'EOF'
#!/bin/sh

[ "$ACTION" = "ifup" ] || exit 0

# === 1. 接口过滤 (安全核心) ===
case "$INTERFACE" in
    # 🚫 屏蔽 IPTV 接口
    iptv*|IPTV*|eth0.3) exit 0 ;;
    # ✅ 仅允许 WAN 接口
    wan|wan0|internet) : ;;
    *) exit 0 ;;
esac

sleep 2

# === 获取网络信息 ===
GATEWAY=$(ip route show default 2>/dev/null | awk '/default via/ {print $3; exit}')
DEV=$(ip route show default 2>/dev/null | awk '/default via/ {print $5; exit}')

# 基础检查
[ -z "$GATEWAY" ] || [ -z "$DEV" ] && { logger -t wan-firewall "WAN 未就绪"; exit 1; }

# 二次安全校验
if [ "$DEV" = "eth0.3" ]; then
    logger -t wan-firewall "⚠️ 警告: 网关指向 IPTV 接口，拒绝开放权限！"
    exit 1
fi

CIDR=$(ip addr show "$DEV" 2>/dev/null | awk '/inet / && !/127.0.0.1/ {print $2; exit}')
[ -z "$CIDR" ] && { logger -t wan-firewall "WAN 无 IPv4 地址"; exit 1; }

MASK=${CIDR#*/}
UPSTREAM_CIDR="$GATEWAY/$MASK"

# === 安全加固：设置 wan.input = REJECT ===
WAN_ZONE_UPDATED=0
for i in $(seq 0 10); do
    if uci get firewall.@zone[$i].name 2>/dev/null | grep -q "^wan$"; then
        current=$(uci get firewall.@zone[$i].input 2>/dev/null)
        if [ "$current" != "REJECT" ]; then
            uci set firewall.@zone[$i].input='REJECT'
            WAN_ZONE_UPDATED=1
        fi
        break
    fi
done

# === 创建管理规则 (合并 80 和 22) ===
# 先清理旧规则，防止重复
uci -q delete firewall.allow_wan_luci
uci -q delete firewall.allow_wan_ssh
uci -q delete firewall.allow_wan_manage

# 创建新规则
uci set firewall.allow_wan_manage=rule
uci set firewall.allow_wan_manage.name='Allow-Management-From-Upstream'
uci set firewall.allow_wan_manage.src='wan'
uci set firewall.allow_wan_manage.src_ip="$UPSTREAM_CIDR"
uci set firewall.allow_wan_manage.proto='tcp'
# ✨ 关键修改：用空格分隔多个端口
uci set firewall.allow_wan_manage.dest_port='80 22'
uci set firewall.allow_wan_manage.target='ACCEPT'

# === 配置 uHTTPd ===
current_rfc=$(uci get uhttpd.main.rfc1918_filter 2>/dev/null)
if [ "$current_rfc" != "0" ]; then
    uci set uhttpd.main.rfc1918_filter='0'
fi

# === 统一提交并重载 ===
uci commit firewall
uci commit uhttpd

# 只需 reload 一次
/etc/init.d/firewall reload >/dev/null 2>&1
/etc/init.d/uhttpd reload >/dev/null 2>&1

logger -t wan-firewall "✅ WAN 管理规则已更新：允许 $UPSTREAM_CIDR 访问 Web(80) 和 SSH(22)"
EOF
chmod +x files/etc/hotplug.d/iface/99-autodetect-wan-rule
echo "✅ 已创建合并端口版 hotplug 脚本"


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
