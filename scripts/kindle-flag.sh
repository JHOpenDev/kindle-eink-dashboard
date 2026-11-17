#!/bin/bash
# 设置/清除 Kindle USB 卷上的 emergency.sh 标志文件，并强制 sync。
# 背景：直接 touch 后立刻拔线，macOS 的 FAT 缓存可能没落盘，设备侧看不到标志；
# 反过来设备侧 rm 标志后若不 sync，FAT 会回滚把标志"复活"。
# 用法: kindle-flag.sh <set|clear|ls> [start_koread|weread_stop|nosleep|dashboard_stop]
# 默认开机进入微信读书；set weread_stop 后重启进入看板，clear weread_stop 恢复。
set -e

usage() { echo "用法: kindle-flag.sh <set|clear|ls> [标志名]" >&2; exit 1; }
[ $# -ge 1 ] || usage
ACTION="$1"; FLAG="$2"

# 通过 emergency.sh 这个锚点文件找到 Kindle 卷（卷名不固定）
VOL=""
for v in /Volumes/*; do
    [ -f "$v/emergency.sh" ] && VOL="$v" && break
done
if [ -z "$VOL" ]; then
    echo "未找到 Kindle 卷（先插线），/Volumes/ 内容:" >&2
    ls /Volumes/ >&2
    exit 1
fi

case "$ACTION" in
    set)
        [ -n "$FLAG" ] || usage
        touch "$VOL/$FLAG"
        sync
        ;;
    clear)
        [ -n "$FLAG" ] || usage
        rm -f "$VOL/$FLAG"
        sync
        ;;
    ls)
        ;;
    *)
        usage
        ;;
esac

echo "Kindle 卷: $VOL，当前标志:"
ls -la "$VOL" | grep -E "start_koread|weread_stop|nosleep|dashboard_stop|start_weread" || echo "  (无)"
echo ""
echo "下一步: 全部文件部署完 -> diskutil eject \"$VOL\" -> 再拔线"
