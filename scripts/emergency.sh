#!/bin/sh
# Deploy raw-frame pipeline: fetch dash.raw -> write /dev/fb0 -> fbink refresh
cat > /mnt/us/dashboard/local/fetch-dashboard.sh << 'FETCHEOF'
#!/usr/bin/env sh
OUT="$1"
"$(dirname "$0")/../xh" -d -q --timeout 15 -o "$OUT.raw" get http://192.168.1.210:8899/dash.raw || exit 1
[ "$(wc -c < "$OUT.raw")" -eq 1575424 ] || exit 1
cat "$OUT.raw" > /dev/fb0
/mnt/us/libkh/bin/fbink -f -s
mv "$OUT.raw" "$OUT"
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

stop_framework() {
  initctl stop framework >/dev/null 2>&1
  initctl stop webreader >/dev/null 2>&1
  lipc-set-prop com.lab126.powerd preventScreenSaver 1
}

refresh_dashboard() {
  stop_framework
  "$DIR/wait-for-wifi.sh" "$WIFI_TEST_IP"
  "$FETCH_DASHBOARD_CMD" "$DASH_PNG" || { echo "fetch failed"; return 1; }
}

rtc_sleep() {
  duration=${1:-300}
  if [ -d /sys/class/rtc/rtc0 ]; then
    echo 0 >/sys/class/rtc/rtc0/wakealarm 2>/dev/null
    echo "$(( $(date +%s) + duration ))" >/sys/class/rtc/rtc0/wakealarm 2>/dev/null
  fi
  echo "mem" >/sys/power/state
}

main_loop() {
  while true; do
    echo "$(date) Battery: $(gasgauge-info -c)."
    next_wakeup_secs=$("$DIR/next-wakeup" --schedule="$REFRESH_SCHEDULE" --timezone="$TIMEZONE")
    refresh_dashboard
    sleep 10
    rtc_sleep "$next_wakeup_secs"
  done
}

stop_framework
/etc/init.d/framework stop >/dev/null 2>&1
echo powersave >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
main_loop
DASHEOF
chmod +x /mnt/us/dashboard/dash.sh
rm -f /mnt/us/dashboard/logs/dash.log

if ps | grep -v grep | grep -q "dashboard/dash.sh"; then
    exit 0
fi
/mnt/us/dashboard/start.sh
