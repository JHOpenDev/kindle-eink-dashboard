#!/usr/bin/env python3
"""拉取 Open-Meteo 北京实时天气 → weather_data.js（供 dashboard.html 渲染注入）"""
import json
import urllib.request
import sys

URL = ("https://api.open-meteo.com/v1/forecast"
       "?latitude=39.9042&longitude=116.4074"
       "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
       "&daily=temperature_2m_max,temperature_2m_min,weather_code"
       "&timezone=Asia%2FShanghai&forecast_days=1")

WMO = {
    0: "晴", 1: "基本晴", 2: "多云转晴", 3: "阴",
    45: "雾", 48: "雾凇",
    51: "毛毛雨", 53: "毛毛雨", 55: "毛毛雨",
    61: "小雨", 63: "中雨", 65: "大雨",
    66: "冻雨", 67: "冻雨",
    71: "小雪", 73: "中雪", 75: "大雪", 77: "雪粒",
    80: "阵雨", 81: "阵雨", 82: "强阵雨",
    85: "阵雪", 86: "阵雪",
    95: "雷暴", 96: "雷暴冰雹", 99: "雷暴冰雹",
}

OUT = "/Users/JH/Documents/ZCode/工具/kindle-eink-dashboard/render/weather_data.js"

try:
    with urllib.request.urlopen(URL, timeout=10) as r:
        d = json.load(r)
    cur = d["current"]
    code = cur["weather_code"]
    desc = WMO.get(code, f"天气{code}")
    daily = d["daily"]
    dcode = daily["weather_code"][0]
    data = {
        "temp": round(cur["temperature_2m"]),
        "desc": desc,
        "humidity": cur["relative_humidity_2m"],
        "wind": round(cur["wind_speed_10m"]),
        "tmax": round(daily["temperature_2m_max"][0]),
        "tmin": round(daily["temperature_2m_min"][0]),
        "ddesc": WMO.get(dcode, desc),
        "city": "北京",
    }
    js = "window.WEATHER = " + json.dumps(data, ensure_ascii=False) + ";"
    open(OUT, "w").write(js)
    print(f"OK: 北京 {data['temp']}°C {data['desc']} 湿度{data['humidity']}% "
          f"{data['tmin']}~{data['tmax']}°C")
except Exception as e:
    print(f"WARN: 天气拉取失败（保留上次数据）: {e}", file=sys.stderr)
    sys.exit(0)  # 网络失败不阻塞渲染，沿用旧数据
