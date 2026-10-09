#!/bin/bash
#
# diy-part1.sh - 在 feeds update 之前执行
#
# feeds 源已由仓库根目录的 feeds.conf.default 整体提供
# （workflow 会执行: [ -e feeds.conf.default ] && mv feeds.conf.default openwrt/feeds.conf.default）
# 这里只做输出确认，方便在 Actions 日志里核对
#

echo "===== diy-part1: 当前 feeds 配置 ====="
cat feeds.conf.default

echo "===== diy-part1: 完成 ====="
