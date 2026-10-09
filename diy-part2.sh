#!/bin/bash
#
# diy-part2.sh - 在 feeds install -a 之后、make defconfig 之前执行
#

echo "===== diy-part2: 开始 ====="

# ---------------------------------------------------------------------------
# 1) EasyTier 使用官方预编译二进制，其 Makefile 里 RSTRIP:=: 关闭了 strip
#    打开 strip 可显著缩小体积（Rust 二进制符号表很大）
# ---------------------------------------------------------------------------
for f in feeds/easytier/easytier-noweb/Makefile feeds/easytier/easytier/Makefile; do
    if [ -f "$f" ]; then
        sed -i 's|^RSTRIP:=:|RSTRIP:=$(TARGET_CROSS)strip|' "$f"
        echo "[OK] 已为 $f 开启 strip"
    fi
done

# ---------------------------------------------------------------------------
# 2) 兜底：easytier 的版本宏（feeds install 可能不会把 feed 根目录的 version.mk 带过去）
# ---------------------------------------------------------------------------
if [ ! -f feeds/easytier/version.mk ]; then
    echo "EASYTIER_VERSION=2.6.4" > feeds/easytier/version.mk
    echo "[OK] 补写 feeds/easytier/version.mk"
fi

# ---------------------------------------------------------------------------
# 3) files/ 目录里的脚本需要可执行位（GitHub 上传的文件默认 644）
# ---------------------------------------------------------------------------
if [ -d files ]; then
    find files -type f \( -name '*.sh' -o -path '*/uci-defaults/*' -o -path '*/init.d/*' \) -exec chmod +x {} \;
    echo "[OK] files/ 内脚本已加可执行位"
fi

# ---------------------------------------------------------------------------
# 3b) 直接把 wifi-tune 挂到 rc.d，保证【第一次开机】就会执行
#     （uci-defaults 里再 enable 一次只是双保险，否则要等第二次开机才生效）
# ---------------------------------------------------------------------------
if [ -d files/etc/init.d ]; then
    mkdir -p files/etc/rc.d
    ln -sf ../init.d/wifi-tune files/etc/rc.d/S99wifi-tune
    echo "[OK] 已挂载 /etc/rc.d/S99wifi-tune"
    ls -l files/etc/rc.d/
fi

# ---------------------------------------------------------------------------
# 4) 打印关键选择，便于在 Actions 日志中核对本次编译内容
# ---------------------------------------------------------------------------
echo "----- 关键功能开关 -----"
grep -E '^CONFIG_PACKAGE_(luci-app-passwall|luci-app-adblock|adblock|luci-app-easytier|easytier-noweb|xray-core|luci-app-commands|luci-app-zerotier|luci-app-upnp|luci-theme-argon|block-mount)=' .config || true
echo "----- 已关闭的（应为空）-----"
grep -E '^CONFIG_PACKAGE_(luci-app-zerotier|luci-app-upnp|luci-theme-argon|block-mount)=' .config || true
echo "----- 中文语言包 -----"
grep -c '^CONFIG_PACKAGE_luci-i18n-.*-zh-cn=y' .config

echo "===== diy-part2: 完成 ====="
