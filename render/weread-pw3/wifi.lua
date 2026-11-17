-- Kindle Wi-Fi 重连：awesome 被 SIGSTOP 后系统界面不会替我们恢复无线，
-- 因此请求层要在重试 HTTP 之前主动检查并拉起 wirelessEnable。
local logger = require("logger")
local util = require("ffi/util")

local M = {
    RECONNECT_INTERVAL = 12,
    WAIT_SECONDS = 45,
}

local LAST_ATTEMPT_FILE = "/tmp/weread-wifi-last-attempt"

local function lipcGet(service, property)
    local p = io.popen(string.format("lipc-get-prop %s %s 2>/dev/null", service, property))
    if not p then return nil end
    local value = p:read("*l")
    p:close()
    if not value then return nil end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function wirelessEnable(enabled)
    os.execute(string.format(
        "lipc-set-prop com.lab126.cmd wirelessEnable %d >/dev/null 2>&1",
        enabled and 1 or 0))
end

local function lastAttempt()
    local f = io.open(LAST_ATTEMPT_FILE, "r")
    if not f then return 0 end
    local value = tonumber(f:read("*a") or "") or 0
    f:close()
    return value
end

local function markAttempt(now)
    local f = io.open(LAST_ATTEMPT_FILE, "w")
    if not f then return end
    f:write(tostring(now))
    f:close()
end

function M.isConnected()
    return lipcGet("com.lab126.wifid", "cmState") == "CONNECTED"
end

-- 未连接时主动拉起无线；开关已打开但仍未关联时先关再开。
-- /tmp 中的时间戳让主进程与下载子进程共享 12 秒防抖窗口。
function M.ensureConnected()
    if M.isConnected() then return true end
    local now = os.time()
    local elapsed = now - lastAttempt()
    -- 系统时间回拨时不要被旧时间戳永久卡住。
    if elapsed >= 0 and elapsed < M.RECONNECT_INTERVAL then return false end
    markAttempt(now)

    if lipcGet("com.lab126.cmd", "wirelessEnable") == "1" then
        logger.info("weread wifi: enabled but disconnected, cycling wireless")
        wirelessEnable(false)
        util.usleep(500000)
    else
        logger.info("weread wifi: enabling wireless")
    end
    wirelessEnable(true)
    return M.isConnected()
end

-- 在子进程中使用：等待关联完成，不主动阻塞 HTTP 请求线程做无谓重试。
function M.waitForConnection(seconds)
    local socket = require("socket")
    local deadline = socket.gettime() + (seconds or M.WAIT_SECONDS)
    repeat
        if M.isConnected() then return true end
        M.ensureConnected()
        if socket.gettime() >= deadline then break end
        util.usleep(1500000)
    until false
    return M.isConnected()
end

return M
