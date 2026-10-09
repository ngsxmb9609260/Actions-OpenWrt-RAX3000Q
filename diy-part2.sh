#!/bin/bash
#
# diy-part2.sh - 在 feeds install -a 之后、make defconfig 之前执行
#

echo "===== diy-part2: 开始 ====="

# ---------------------------------------------------------------------------
# 1) 【重要·切勿再改】EasyTier 的 Makefile 必须保留官方 RSTRIP:=:
#
#    easytier feed 用的是官方预编译二进制，它的 install 段会把【整个包目录】
#    当作 $(RSTRIP) 的入参；一旦把 RSTRIP 换成真的 strip，打包阶段必然崩：
#       arm-...-strip: Warning: '.../ipkg-arm_cortex-a7_neon-vfpv4/easytier-noweb' is a directory
#       make[3]: *** [Makefile:87: .../easytier-noweb_2.6.4_...ipk] Error 1
#       make: *** [include/toplevel.mk:230: world] Error 2
#    2026-10-10 首次云编译正是死在这一行（详见 .workbuddy/memory/2026-10-10.md）。
#
#    代价只是固件大几 MB（Rust 符号表），对 128MB NAND 完全无压力 —— 不换。
# ---------------------------------------------------------------------------
echo "[INFO] 保持 easytier 官方 RSTRIP:=:（强开 strip 会导致 ipk 打包失败）"

# ---------------------------------------------------------------------------
# 2) 兜底：easytier 的版本宏（feeds install 可能不会把 feed 根目录的 version.mk 带过去）
# ---------------------------------------------------------------------------
if [ ! -f feeds/easytier/version.mk ]; then
    echo "EASYTIER_VERSION=2.6.4" > feeds/easytier/version.mk
    echo "[OK] 补写 feeds/easytier/version.mk"
fi

# ---------------------------------------------------------------------------
# 2b) 【重要】xray-core 包版本必须与 Go 工具链匹配
#
#    packages feed 自带的 xray-core 1.8.3 锁定了 2022-09 的 gvisor 依赖快照，
#    其 pkg/gohacks 唯一文件的构建标签是 `go1.13 && !go1.21` —— workflow 的
#    「Fix golang version」用 Go 1.25（kenzok8/golang -b 1.25）编译时，
#    该目录下所有文件被 build constraints 排除，xray-core 必然编译失败：
#       imports gvisor.dev/gvisor/pkg/gohacks: build constraints exclude all Go files
#       ERROR: package/feeds/packages/xray-core failed to build
#    2026-10-10 第 2 次云编译正是死在这里（run 37961191310）。
#
#    修法：升级到 v25.9.11（go.mod 要求 go 1.25、gvisor 2025-04 快照，
#    与 go1.25.14 匹配）。PKG_HASH 为 codeload 源码包实测 SHA256。
#    注意：最新版不能用（v26.3.27 要求 go 1.27，超出工具链）。
# ---------------------------------------------------------------------------
XRAY_DIR=feeds/packages/net/xray-core
if [ -f "$XRAY_DIR/Makefile" ] && grep -q '^PKG_VERSION:=1\.8\.3' "$XRAY_DIR/Makefile"; then
    sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:=25.9.11/'  "$XRAY_DIR/Makefile"
    sed -i 's/^PKG_HASH:=.*/PKG_HASH:=9bccd2681183698bf860b1af5407f97b4b60090324aa3ef1546e446612d44e1f/' "$XRAY_DIR/Makefile"
    echo "[OK] xray-core 已升级: 1.8.3 -> 25.9.11（兼容 Go 1.25）"
    grep -E '^PKG_(VERSION|HASH):=' "$XRAY_DIR/Makefile"
else
    echo "[WARN] 未找到 xray-core 1.8.3 的 Makefile（可能 feed 已更新），跳过升级"
    grep -E '^PKG_VERSION:=' "$XRAY_DIR/Makefile" 2>/dev/null || true
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
