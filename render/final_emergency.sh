#!/bin/sh
# Kindle PW3 开机入口：默认微信读书，weread_stop 存在时进入看板。
# 看板管线：fetch dash.raw -> write /dev/fb0 -> fbink refresh

# === BOOT TRACE (unconditional) ===
# Ground truth: what the DEVICE sees in /mnt/us at bridge-time. Answers "did
# the flag reach the device" once and for all. Keep for a few debug cycles.
{
    echo "=== emergency.sh entered $(date) ==="
    echo "--- device view of /mnt/us root (flags & anchors) ---"
    ls -la /mnt/us 2>&1 | grep -E "start_koread|weread_stop|nosleep|dashboard_stop|start_weread|emergency|koreader|weread" || echo "(no matching entries visible)"
    echo "--- flag tests ---"
    echo "-f start_koread: $( [ -f /mnt/us/start_koread ] && echo YES || echo no )"
    echo "-f weread_stop: $( [ -f /mnt/us/weread_stop ] && echo YES || echo no )"
    echo "-f dashboard_stop: $( [ -f /mnt/us/dashboard_stop ] && echo YES || echo no )"
    echo "-f nosleep: $( [ -f /mnt/us/nosleep ] && echo YES || echo no )"
} >>/mnt/us/boot_trace.log 2>&1

# 崩溃转储防线：framework 崩溃时每个 core 约 196MB，15 个就塞满 3GB 分区
# （2026-11-16 事故：磁盘 100% → 全系统写失败）。内核级重定向 + shell 级双保险。
echo "/dev/null" > /proc/sys/kernel/core_pattern 2>/dev/null
ulimit -c 0 2>/dev/null
# 同时清理历史转储；只匹配崩溃产物扩展名，不动 documents 里的书籍。
rm -f /mnt/us/*.core 2>/dev/null
if [ -d /mnt/us/documents ]; then
    find /mnt/us/documents -maxdepth 1 \
        \( -name '*.core' -o -name '*.crash' -o -name 'crash-*.log' -o -name 'crash-*.txt' \) \
        -exec rm -rf '{}' \; 2>/dev/null
fi

# 主动打开无线。App 内的 weread/wifi.lua 还会在断线时负责重连。
lipc-set-prop com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1

# 开机关背光（前光纯软件控制；看板模式下系统 UI 已死，只能开机时设）
lipc-set-prop com.lab126.powerd flIntensity 0

cat > /mnt/us/dashboard/local/fetch-dashboard.sh << 'FETCHEOF'
#!/usr/bin/env sh
OUT="$1"
"$(dirname "$0")/../xh" -d -q --timeout 15 -o "$OUT.raw" get http://192.168.1.210:8899/dash.raw || exit 1
[ "$(wc -c < "$OUT.raw")" -eq 1575424 ] || exit 1
cat "$OUT.raw" > /dev/fb0
/mnt/us/libkh/bin/fbink -f -s
mv "$OUT.raw" "$OUT"
# NOTE: sleep.png 归微信读书 App 所有（App 内定时拉天气重绘），看板不要碰它
FETCHEOF
chmod +x /mnt/us/dashboard/local/fetch-dashboard.sh

cat > /mnt/us/dashboard/dash.sh << 'DASHEOF'
#!/usr/bin/env sh
DIR="$(dirname "$0")"
DASH_PNG="$DIR/dash.png"
FETCH_DASHBOARD_CMD="$DIR/local/fetch-dashboard.sh"
REFRESH_SCHEDULE=${REFRESH_SCHEDULE:-"*/5 * * * *"}
SLEEP_SCREEN_INTERVAL=${SLEEP_SCREEN_INTERVAL:-3600}
TIMEZONE=${TIMEZONE:-"Asia/Shanghai"}
WIFI_TEST_IP=${WIFI_TEST_IP:-1.1.1.1}
num_refresh=0

# 防挂死：initctl/lipc/电量计在异常状态（如深度亏电后）可能永久阻塞。
# timeout 可用则加超时，不可用则原样执行。
tmo() {
  if command -v timeout >/dev/null 2>&1; then
    local d="$1"; shift; timeout "$d" "$@"
  else
    shift; "$@"
  fi
}

stop_framework() {
  tmo 10 initctl stop framework >/dev/null 2>&1
  tmo 10 initctl stop webreader >/dev/null 2>&1
  tmo 5 lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1
}

refresh_dashboard() {
  stop_framework
  tmo 45 "$DIR/wait-for-wifi.sh" "$WIFI_TEST_IP"
  "$FETCH_DASHBOARD_CMD" "$DASH_PNG" || { echo "fetch failed"; return 1; }
}

rtc_sleep() {
  duration=${1:-300}
  if [ -f /mnt/us/nosleep ]; then
    echo "nosleep flag present, shallow sleep"
    sleep 60
    return
  fi
  if [ -d /sys/class/rtc/rtc0 ]; then
    echo 0 >/sys/class/rtc/rtc0/wakealarm 2>/dev/null
    echo "$(( $(date +%s) + duration ))" >/sys/class/rtc/rtc0/wakealarm 2>/dev/null
  fi
  echo "mem" >/sys/power/state
}

main_loop() {
  while true; do
    echo "$(date) Battery: $(tmo 8 gasgauge-info -c 2>/dev/null || echo '?')."
    next_wakeup_secs=$(tmo 10 "$DIR/next-wakeup" --schedule="$REFRESH_SCHEDULE" --timezone="$TIMEZONE")
    refresh_dashboard
    sleep 10
    rtc_sleep "$next_wakeup_secs"
  done
}

# 白屏急救：先把磁盘上最后一张看板画上（framework 停止后 fb 无人写就是白屏）
if [ -s "$DASH_PNG" ]; then
  cat "$DASH_PNG" > /dev/fb0
  /mnt/us/libkh/bin/fbink -f -s
fi

stop_framework
tmo 15 /etc/init.d/framework stop >/dev/null 2>&1
echo powersave >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
main_loop
DASHEOF
chmod +x /mnt/us/dashboard/dash.sh
rm -f /mnt/us/dashboard/logs/dash.log

# 微信读书是默认主页；weread_stop 存在时才退回看板。
# start_koread 保留为兼容/强制进入入口，并会清除 weread_stop。
# 3 分钟窗口内最多拉起 4 次，避免启动异常形成反复重启。
WEREAD_GUARD_FILE=/var/local/weread-launch.guard
weread_launch_allowed() {
    local now window_start count elapsed
    now=$(date +%s)
    window_start=$now
    count=0
    if [ -f "$WEREAD_GUARD_FILE" ]; then
        set -- $(cat "$WEREAD_GUARD_FILE" 2>/dev/null)
        case "${1:-}" in
            ''|*[!0-9]*) window_start=$now ;;
            *) window_start=$1 ;;
        esac
        case "${2:-0}" in
            ''|*[!0-9]*) count=0 ;;
            *) count=$2 ;;
        esac
    fi
    elapsed=$((now - window_start))
    if [ "$elapsed" -lt 0 ] || [ "$elapsed" -ge 180 ]; then
        window_start=$now
        count=0
    fi
    if [ "$count" -ge 4 ]; then
        echo "$(date) weread launch guard: 4 launches within 180s, fallback to dashboard" >>/mnt/us/weread/boot.log 2>&1
        return 1
    fi
    count=$((count + 1))
    printf '%s %s\n' "$window_start" "$count" >"$WEREAD_GUARD_FILE.tmp" \
        && mv "$WEREAD_GUARD_FILE.tmp" "$WEREAD_GUARD_FILE"
    return 0
}

if [ -f /mnt/us/start_koread ]; then
    rm -f /mnt/us/start_koread /mnt/us/weread_stop
    sync
fi

if [ ! -f /mnt/us/weread_stop ] && [ -f /mnt/us/weread/run.sh ]; then
    # bridge.conf 在 upstart pre-start 同步执行本脚本；run.sh 必须后台化。
    # 若 emergency.sh 被重复触发，不重复启动已存活的 App。
    if ps | grep -v grep | grep -q "weread/main.lua"; then
        exit 0
    fi
    if weread_launch_allowed; then
        {
            echo "=== $(date) launching WeRead (bridge CWD=$(pwd)) ==="
            echo "--- key files ---"
            ls -ld /mnt/us/koreader /mnt/us/weread 2>&1
            ls -la /mnt/us/weread/run.sh /mnt/us/weread/main.lua /mnt/us/koreader/luajit /mnt/us/koreader/reader.lua 2>&1
            echo "--- KOREADER_DIR env pollution check ---"
            env | grep -i koreader
            echo "--- run.sh first 40 lines ---"
            head -40 /mnt/us/weread/run.sh 2>&1
            echo "--- launching run.sh (sh -x, backgrounded) ---"
        } >>/mnt/us/weread/boot.log 2>&1
        nohup /bin/sh -x /mnt/us/weread/run.sh >>/mnt/us/weread/boot.log 2>&1 &
        echo "=== $(date) run.sh backgrounded (pid $!) ===" >>/mnt/us/weread/boot.log 2>&1
        exit 0
    fi
fi

if [ -f /mnt/us/dashboard_stop ]; then
    echo "dashboard_stop present, skip all autostart" >>/mnt/us/boot_trace.log 2>&1
    exit 0
fi
if ps | grep -v grep | grep -q "dashboard/dash.sh"; then
    exit 0
fi
/mnt/us/dashboard/start.sh
