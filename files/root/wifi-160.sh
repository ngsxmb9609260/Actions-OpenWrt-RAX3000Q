#!/bin/sh
#
# wifi-160.sh - 一键切换 5G 频宽（160MHz 高速 / 80MHz 稳定）
#
# 用法：
#   wifi-160.sh 160    切换到 160MHz（理论 2402Mbps，但会踩 DFS 雷达避让，可能偶发断线）
#   wifi-160.sh 80     切回 80MHz（推荐，稳定优先）
#   wifi-160.sh        查看当前 5G 频宽状态
#
# 说明：国内 5GHz 的 160MHz 只能落在 36-64，其中 52-64 属于 DFS 频段。
#       只要有一个子信道检测到雷达信号，整块 160MHz 都会被放弃，客户端会短暂断线。
#       所以日常建议 80MHz；需要跑满速时再临时切 160MHz。
#

find_5g_dev() {
	for s in $(uci -q show wireless | sed -n 's/^wireless\.\([^.]*\)=wifi-device$/\1/p'); do
		if [ "$(uci -q get wireless."$s".band)" = '5g' ]; then
			echo "$s"
			return 0
		fi
	done
	return 1
}

DEV="$(find_5g_dev)"

if [ -z "$DEV" ]; then
	echo "错误：没有找到 5G 射频设备，请确认无线驱动已加载（logread | grep ath11k）"
	exit 1
fi

case "$1" in
	160|160m|160MHz)
		# 160MHz 需要连续 8 个 20MHz 子信道，主信道只能落在 36
		uci -q set wireless."$DEV".htmode='HE160'
		uci -q set wireless."$DEV".channel='36'
		uci -q commit wireless
		wifi reload >/dev/null 2>&1
		echo "已切换：5G → HE160 @ 信道 36（高速模式）"
		echo "提示：若出现十几秒的集体断线，那是 DFS 雷达避让在生效，用本脚本切回 80 即可。"
		;;
	80|80m|80MHz)
		# 44 是非 DFS 信道，永不触发雷达避让
		uci -q set wireless."$DEV".htmode='HE80'
		uci -q set wireless."$DEV".channel='44'
		uci -q commit wireless
		wifi reload >/dev/null 2>&1
		echo "已切换：5G → HE80 @ 信道 44（稳定模式）"
		;;
	'')
		echo "当前 5G 射频：$DEV"
		echo "  信道   : $(uci -q get wireless."$DEV".channel)"
		echo "  频宽   : $(uci -q get wireless."$DEV".htmode)"
		echo "  区域码 : $(uci -q get wireless."$DEV".country)"
		echo ""
		echo "用法：wifi-160.sh 160  |  wifi-160.sh 80"
		;;
	*)
		echo "参数无效：$1"
		echo "用法：wifi-160.sh 160  |  wifi-160.sh 80"
		exit 1
		;;
esac

exit 0
