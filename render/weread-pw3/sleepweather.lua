-- 息屏天气图：定时拉 Open-Meteo 实时天气，把 /mnt/us/weread/sleep.png 重绘成天气版。
-- 设备长期待在微信读书里时屏保也保持新鲜；hookScreensaver（app.lua）优先使用这个文件。
-- 渲染跑在子进程（Async.run，同 prepareSleepImage 的先例），失败时保留旧图。
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local logger = require("logger")
local rapidjson = require("rapidjson")
local TextWidget = require("ui/widget/textwidget")
local Screen = Device.screen

local Config = require("weread/config")
local Theme = require("weread/theme")

local W, H = Screen:getWidth(), Screen:getHeight()
local URL = ("https://api.open-meteo.com/v1/forecast"
    .. "?latitude=39.9042&longitude=116.4074"
    .. "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
    .. "&daily=temperature_2m_max,temperature_2m_min&timezone=Asia%2FShanghai&forecast_days=1")

local M = { REFRESH_SECONDS = 1800 }

local WMO = {
    [0] = "晴", [1] = "基本晴", [2] = "多云转晴", [3] = "阴",
    [45] = "雾", [48] = "雾凇",
    [51] = "毛毛雨", [53] = "毛毛雨", [55] = "毛毛雨",
    [61] = "小雨", [63] = "中雨", [65] = "大雨",
    [66] = "冻雨", [67] = "冻雨",
    [71] = "小雪", [73] = "中雪", [75] = "大雪", [77] = "雪粒",
    [80] = "阵雨", [81] = "阵雨", [82] = "强阵雨",
    [85] = "阵雪", [86] = "阵雪",
    [95] = "雷暴", [96] = "雷暴冰雹", [99] = "雷暴冰雹",
}

local function httpGet(url, timeout)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local chunks = {}
    socketutil:set_timeout(timeout or 10, timeout or 30)
    local ok, code = http.request{
        url = url,
        method = "GET",
        sink = ltn12.sink.table(chunks),
    }
    socketutil:reset_timeout()
    if not ok or type(code) ~= "number" or code ~= 200 then return nil end
    local body = table.concat(chunks)
    local ok2, data = pcall(rapidjson.decode, body)
    if not ok2 or type(data) ~= "table" then return nil end
    return data
end

local function centered(bb, text, weight, px, y, gray)
    local tw = TextWidget:new{
        text = text,
        face = Theme.face(weight, px),
        fgcolor = gray and Blitbuffer.Color8(gray) or Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    local w = tw:size().w
    tw:paintTo(bb, math.floor((W - w) / 2), y)
    tw:free()
end

local function render(data)
    local cur, daily = data.current, data.daily
    local desc = WMO[cur.weather_code] or "—"
    local round = function(v) return math.floor((v or 0) + 0.5) end

    local bb = Blitbuffer.new(W, H, Screen.bb:getType())
    bb:paintRect(0, 0, W, H, Blitbuffer.COLOR_WHITE)

    local t = os.date("*t")
    local weeks = { "日", "一", "二", "三", "四", "五", "六" }
    centered(bb, string.format("%d年%d月%d日 星期%s", t.year, t.month, t.day, weeks[t.wday]),
        "Medium", 54, 140)
    centered(bb, "北京", "Regular", 42, 235, 90)
    centered(bb, string.format("%d°C", round(cur.temperature_2m)), "Bold", 240, 430)
    centered(bb, desc, "Bold", 96, 760)
    bb:paintRect(W / 2 - 90, 920, 180, 3, Blitbuffer.COLOR_BLACK)
    centered(bb, string.format("%d~%d°C · 湿度%d%% · 风%dkm/h",
        round(daily.temperature_2m_min[1]), round(daily.temperature_2m_max[1]),
        round(cur.relative_humidity_2m), round(cur.wind_speed_10m)), "Regular", 44, 980, 60)
    centered(bb, "按电源键继续阅读", "Regular", 40, 1300, 120)

    return bb
end

-- 子进程里跑：拉数据 → 渲染 → 原子落盘。成功返回路径，失败返回 nil（保留旧图）。
function M.refresh()
    local data
    for _ = 1, 3 do
        data = httpGet(URL, 15)
        if data and data.current then break end
        require("ffi/util").usleep(5 * 1000000)
    end
    if not data or not data.current then
        logger.warn("weread sleepweather: fetch failed")
        return nil
    end
    local ok, bb = pcall(render, data)
    if not ok or not bb then
        logger.warn("weread sleepweather: render failed:", bb)
        return nil
    end
    local out = Config.appDir() .. "/sleep.png"
    local tmp = out .. ".tmp"
    bb:writePNG(tmp)
    bb:free()
    os.rename(tmp, out)
    return out
end

function M.refreshAsync(cb)
    local Async = require("weread/async")
    Async.run(M.refresh, function(file)
        if not file then logger.warn("weread sleepweather: refresh failed") end
        if cb then cb(file ~= nil) end
    end)
end

return M
