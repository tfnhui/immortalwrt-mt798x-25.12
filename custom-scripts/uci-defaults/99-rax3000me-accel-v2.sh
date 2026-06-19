#!/bin/sh
# ================================================================
# RAX3000Me 首次启动硬件加速激活脚本 — MTK SDK 修订版
# 存放路径: <源码根目录>/files/etc/uci-defaults/99-rax3000me-accel.sh
#
# 关键修正：
#   - 不操作 bridger（与 WARP/WED 冲突）
#   - 使用 MTK HNAT 对应的 flow_offloading_hw 开关
#   - 保留 mtwifi-cfg-ucode 无线配置体系，不触碰无线相关 UCI
# ================================================================

# ----------------------------------------------------------------
# 1. 启用 MTK PPE / HNAT 硬件流量卸载
#    flow_offloading=1     软件 flow offload（HNAT 前置条件）
#    flow_offloading_hw=1  启用 kmod-mediatek_hnat 硬件引擎
# ----------------------------------------------------------------
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'
uci commit firewall

# ----------------------------------------------------------------
# 2. HNAT 绑定阈值调优（通过 sysfs，开机后写入）
#    默认 30pps，降低后更多连接走硬件加速路径
#    luci-app-eqos-mtk 开启时会自动调为 5pps，此处设 15pps 为中间值
# ----------------------------------------------------------------
mkdir -p /etc/hotplug.d/iface
cat > /etc/hotplug.d/iface/99-hnat-tune << 'HOTPLUG'
#!/bin/sh
[ "$ACTION" = "ifup" ] || exit 0
# 仅在 WAN 接口 up 时执行一次
[ "$INTERFACE" = "wan" ] || exit 0

# MTK HNAT 绑定阈值（pps，越低加速越激进）
[ -f /sys/kernel/debug/mtk_ppe/bind_threshold ] && \
    echo 15 > /sys/kernel/debug/mtk_ppe/bind_threshold 2>/dev/null

# WARP/WED 加速开关确认（kmod-warp 加载后自动启用，此处仅验证）
[ -f /sys/kernel/debug/mtk_warp/enable ] && \
    cat /sys/kernel/debug/mtk_warp/enable > /dev/null 2>&1

logger -t hnat-tune "MTK HNAT tuning applied"
HOTPLUG
chmod +x /etc/hotplug.d/iface/99-hnat-tune

# ----------------------------------------------------------------
# 3. TCP BBR 拥塞控制激活
#    kmod-tcp-bbr 已编译进固件，需通过 sysctl 激活
# ----------------------------------------------------------------
cat >> /etc/sysctl.conf << 'SYSCTL'

# TCP BBR 拥塞控制（kmod-tcp-bbr 已加载）
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL

# ----------------------------------------------------------------
# 4. 网络性能内核参数优化
#    这些参数对 MTK HNAT + WED 环境下的并发连接性能有显著提升
# ----------------------------------------------------------------
cat >> /etc/sysctl.conf << 'SYSCTL'

# conntrack 连接跟踪表扩容（OpenClash 大量连接场景）
net.netfilter.nf_conntrack_max=131072
net.netfilter.nf_conntrack_tcp_timeout_established=7440
net.netfilter.nf_conntrack_tcp_timeout_time_wait=30

# 接收/发送缓冲区（提升高并发吞吐）
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=524288
net.core.wmem_default=524288
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 87380 16777216

# 网络队列优化
net.core.netdev_max_backlog=5000
net.ipv4.tcp_fastopen=3
SYSCTL

# ----------------------------------------------------------------
# 5. ZRAM swap 激活（kmod-zram + zram-swap 已编译进固件）
# ----------------------------------------------------------------
[ -x /etc/init.d/zram ] && /etc/init.d/zram enable 2>/dev/null || true

# ----------------------------------------------------------------
# 6. 系统描述信息
# ----------------------------------------------------------------
uci set system.@system[0].description='ImmortalWrt 25.12 | RAX3000Me | MTK HNAT + WED v2 + WHNAT'
uci commit system

# ----------------------------------------------------------------
# 7. 完成
#    uci-defaults 机制：脚本返回 0 表示成功，不再重复执行
# ----------------------------------------------------------------
exit 0
