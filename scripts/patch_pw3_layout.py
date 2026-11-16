#!/usr/bin/env python3
# PW3 (1072×1448) 布局适配补丁：weread-kindle 界面按 1264×1680 官方稿设计，
# 本脚本在 render/weread-pw3/ 副本上把所有绝对坐标换算成按实际屏幕等比缩放。
# 每处替换都断言唯一命中，避免静默错位。
import sys
from pathlib import Path

D = Path("/Users/JH/Documents/ZCode/工具/kindle-eink-dashboard/render/weread-pw3")
fails = []

def patch(fname, pairs):
    p = D / fname
    s = p.read_text()
    for old, new in pairs:
        n = s.count(old)
        if n != 1:
            fails.append(f"{fname}: 命中 {n} 次（应为 1）: {old[:60]!r}")
            continue
        s = s.replace(old, new)
    p.write_text(s)
    print(f"OK {fname}")

HELPERS = """-- PW3 适配：布局按 1264×1680 官方稿设计，按实际屏幕等比缩放
local SW, SH = Screen:getWidth(), Screen:getHeight()
local function sx(v) return math.floor(v * SW / 1264 + 0.5) end
local function sy(v) return math.floor(v * SH / 1680 + 0.5) end
"""

# ---------- loginview ----------
patch("loginview.lua", [
    ("""local QR_FILE = "/tmp/weread_login_qr.png"
local QR_X, QR_Y, QR_SIZE = 408, 652, 448
local BUTTON = { x = 504, y = 839, w = 256, h = 75 }
local AGREE = { x = 424, y = 1200, w = 416, h = 44 }""",
     """local QR_FILE = "/tmp/weread_login_qr.png"

""" + HELPERS + """local QR_X, QR_Y, QR_SIZE = sx(408), sy(652), sx(448)
local BUTTON = { x = sx(504), y = sy(839), w = sx(256), h = sy(75) }
local AGREE = { x = sx(424), y = sy(1200), w = sx(416), h = sy(44) }"""),
    ('{ "image", 470, 405, Theme.res("login_logo.png"), 330, 85 },',
     '{ "image", sx(470), sy(405), Theme.res("login_logo.png"), sx(330), sy(85) },'),
    ('T(632, 571, self.title, Theme.BOLD, 30, nil, nil, "center"),',
     'T(sx(632), sy(571), self.title, Theme.BOLD, 30, nil, nil, "center"),'),
    ('T(632, 862, label, Theme.BOLD, 28, nil, nil, "center"))',
     'T(sx(632), sy(862), label, Theme.BOLD, 28, nil, nil, "center"))'),
    ('inside(pos, { x = AGREE.x, y = AGREE.y - 10, w = 190, h = AGREE.h + 20 })',
     'inside(pos, { x = AGREE.x, y = AGREE.y - 10, w = sx(190), h = AGREE.h + 20 })'),
])

# ---------- bottombar ----------
patch("bottombar.lua", [
    ("""local TABS = { "store", "shelf", "me" }
local TAB_W = 165
local ICON = 53
local PAGING_X, PAGING_W, PAGING_SPLIT = 994, 270, 1129""",
     """local TABS = { "store", "shelf", "me" }
-- PW3 适配：横向坐标按 1264 设计宽等比缩放
local SX = Screen:getWidth() / 1264
local function sx(v) return math.floor(v * SX + 0.5) end
local TAB_W = sx(165)
local ICON = 53
local PAGING_X, PAGING_W, PAGING_SPLIT = sx(994), sx(270), sx(1129)"""),
    ('{ "image", 44, y0 + 26, Theme.res("icon_toolbar_back.svg"), 53, 53 }',
     '{ "image", sx(44), y0 + 26, Theme.res("icon_toolbar_back.svg"), 53, 53 }'),
    ('{ "image", (i - 1) * TAB_W + 56, y0 + 27, file, ICON, ICON }',
     '{ "image", (i - 1) * TAB_W + sx(56), y0 + 27, file, ICON, ICON }'),
    ('if tab == "back" and pos.x < 141 then return "back" end',
     'if tab == "back" and pos.x < sx(141) then return "back" end'),
])

# ---------- bookpreviewview ----------
patch("bookpreviewview.lua", [
    ("""local W, H = 1264, 1680
local MARGIN_X = 75             -- 封面页左右 40dp""",
     """-- PW3 适配：官方稿 1264×1680，等比缩放到实际屏幕
local W, H = Screen:getWidth(), Screen:getHeight()
local function sx(v) return math.floor(v * W / 1264 + 0.5) end
local function sy(v) return math.floor(v * H / 1680 + 0.5) end
local MARGIN_X = sx(75)          -- 封面页左右 40dp"""),
    ("local tip_ink_bottom = H - 75 - 15",
     "local tip_ink_bottom = H - sy(75) - sy(15)"),
])

# ---------- tocview ----------
patch("tocview.lua", [
    ("""local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")""",
     """local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")"""),
    ("""local ROW_H = 101
local FIRST_ROW = 32          -- 第一行文字顶部（内容坐标）；官方内容区从 y=250 开始，第一行在 282
local BOOKMARK_BTN = { x = 820, w = 150, h = 54 }""",
     HELPERS + """local ROW_H = sy(101)
local FIRST_ROW = sy(32)      -- 第一行文字顶部（内容坐标）
local BOOKMARK_BTN = { x = sx(820), w = sx(150), h = sy(54) }"""),
    ("""        T(45, 58, title, Theme.BOLD, 34, nil, 1030),
        T(1126, 66, "↓去底部", Theme.BOLD, 26),
        { "frame", 45, 125, 1174, 90, 2, Theme.BLACK, 45 },
        { "image", 73, 149, Theme.res("icon_search.png"), 42, 42 },
        T(128, 156, "搜索全书内容", Theme.BOLD, 28, Theme.HINT_GRAY),""",
     """        T(sx(45), sy(58), title, Theme.BOLD, 34, nil, sx(1030)),
        T(sx(1126), sy(66), "↓去底部", Theme.BOLD, 26),
        { "frame", sx(45), sy(125), sx(1174), sy(90), 2, Theme.BLACK, 45 },
        { "image", sx(73), sy(149), Theme.res("icon_search.png"), 42, 42 },
        T(sx(128), sy(156), "搜索全书内容", Theme.BOLD, 28, Theme.HINT_GRAY),"""),
    ("    viewport_top = 250,", "    viewport_top = sy(250),"),
    ('T(1219, y + 6, tostring(page), Theme.REGULAR, 28, nil, nil, "right")',
     'T(sx(1219), y + sy(6), tostring(page), Theme.REGULAR, 28, nil, nil, "right")'),
    ('T(1219, y + 6, string.format("%d%%", bm.percent or 0), Theme.REGULAR, 26, nil, nil, "right")',
     'T(sx(1219), y + sy(6), string.format("%d%%", bm.percent or 0), Theme.REGULAR, 26, nil, nil, "right")'),
    ('T(632, 300, "暂无书签", Theme.BOLD, 30, nil, nil, "center")',
     'T(sx(632), sy(300), "暂无书签", Theme.BOLD, 30, nil, nil, "center")'),
])

# ---------- importguideview ----------
patch("importguideview.lua", [
    ("""local BOX = { x = 129, y = 112, w = 1006, h = 1324, r = 30 }
local PAD = 38
local CLOSE = { size = 105, bottom = 79 }
local TITLE_PX, TEXT_PX = 36, 26
local PIC_W, PIC_H = 926, 453""",
     HELPERS + """local BOX = { x = sx(129), y = sy(112), w = sx(1006), h = sy(1324), r = 30 }
local PAD = sx(38)
local CLOSE = { size = sx(105), bottom = sy(79) }
local TITLE_PX, TEXT_PX = 36, 26
local PIC_W, PIC_H = sx(926), sy(453)"""),
])

# ---------- settingsview ----------
patch("settingsview.lua", [
    ("""local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")""",
     """local Device = require("device")
local Screen = Device.screen
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")"""),
    ("local ROW_TOP, ROW_H = 105, 165",
     HELPERS + "local ROW_TOP, ROW_H = sy(105), sy(165)"),
    ("    local x = 1138", "    local x = sx(1138)"),
    ('{ "hline", 38, y + ROW_H - 2, 1188, 2, Theme.LINE_GRAY }',
     '{ "hline", sx(38), y + ROW_H - 2, sx(1188), 2, Theme.LINE_GRAY }'),
    ('T(632, 33, "设置", Theme.BOLD, 34, nil, nil, "center")',
     'T(sx(632), sy(33), "设置", Theme.BOLD, 34, nil, nil, "center")'),
    ("table.insert(ops, T(38, y + 24, r.title, Theme.BOLD, 32))",
     "table.insert(ops, T(sx(38), y + 24, r.title, Theme.BOLD, 32))"),
])

# ---------- bookdetailview ----------
patch("bookdetailview.lua", [
    ("""local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")""",
     """local Device = require("device")
local Screen = Device.screen
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")"""),
    ("local T = Canvas.text\n\nlocal BUTTONS_Y = 980",
     "local T = Canvas.text\n\n" + HELPERS + "local BUTTONS_Y = sy(980)"),
    ("local cx = 210 + (i - 1) * 422",
     "local cx = sx(210) + (i - 1) * sx(422)"),
    ('T(632, 600, rating, Theme.BOLD, 30, nil, 1100, "center")',
     'T(sx(632), sy(600), rating, Theme.BOLD, 30, nil, sx(1100), "center")'),
    ("T(cx, 680, c.big, Theme.BOLD, 36, nil, nil, \"center\")",
     "T(cx, sy(680), c.big, Theme.BOLD, 36, nil, nil, \"center\")"),
    ("T(cx, 734, c.small, Theme.REGULAR, 24, nil, nil, \"center\")",
     "T(cx, sy(734), c.small, Theme.REGULAR, 24, nil, nil, \"center\")"),
    ('{ "hline", 38, 800, 1188, 2, Theme.LINE_GRAY }',
     '{ "hline", sx(38), sy(800), sx(1188), 2, Theme.LINE_GRAY }'),
    ("Canvas.textBox(38, 830, 1188, b.intro, Theme.REGULAR, 28, nil, 4)",
     "Canvas.textBox(sx(38), sy(830), sx(1188), b.intro, Theme.REGULAR, 28, nil, 4)"),
    ('{ "rect", 38, BUTTONS_Y + 70, 579, 80, Theme.BLACK }',
     '{ "rect", sx(38), BUTTONS_Y + sy(70), sx(579), sy(80), Theme.BLACK }'),
])

# ---------- underlinereviewsview ----------
patch("underlinereviewsview.lua", [
    ("""local UIManager = require("ui/uimanager")""",
     """local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")"""),
    ("""local L, W = 257, 750              -- 卡片左边、宽
local PAD = 37                      -- 卡片内边距
local QUOTE = { y = 58, h = 155, split = 865 }
local GAP = 20                      -- 卡片间距
local CONTENT_PX, CONTENT_PITCH = 36, 51
local WRITE_BTN = { x = 780, y = 1595, w = 191, h = 70 }""",
     HELPERS + """local L, W = sx(257), sx(750)       -- 卡片左边、宽
local PAD = sx(37)                  -- 卡片内边距
local QUOTE = { y = sy(58), h = sy(155), split = sx(865) }
local GAP = sx(20)                  -- 卡片间距
local CONTENT_PX, CONTENT_PITCH = 36, sy(51)
local WRITE_BTN = { x = sx(780), y = sy(1595), w = sx(191), h = sy(70) }"""),
])

# ---------- readerview（阶段一：工具栏/顶栏/购买栏；弹出面板内部留待阶段二） ----------
patch("readerview.lua", [
    ("local T = Canvas.text\n\n-- 墨水屏连续局刷会留残影",
     "local T = Canvas.text\n\n" + HELPERS + "-- 墨水屏连续局刷会留残影"),
    ("local TOP_BAR_H = 137", "local TOP_BAR_H = sy(137)"),
    ("""local TOP_ICONS = {
    { id = "bookmark", x = 618 },
    { id = "review", x = 756, icon = "icon_toolbar_show_idea.svg" },
    { id = "graffiti", x = 894, icon = "icon_reader_note_graffiti.svg" },""",
     """local TOP_ICONS = {
    { id = "bookmark", x = sx(618) },
    { id = "review", x = sx(756), icon = "icon_toolbar_show_idea.svg" },
    { id = "graffiti", x = sx(894), icon = "icon_reader_note_graffiti.svg" },"""),
    ('{ id = "shelf", x = 1032, icon = "icon_toolbar_bookshelf_added.svg" },',
     '{ id = "shelf", x = sx(1032), icon = "icon_toolbar_bookshelf_added.svg" },'),
    ('{ id = "download", x = 1170 },', '{ id = "download", x = sx(1170) },'),
    ("""local BOTTOM_BUTTONS = {
    { id = "back", x0 = 0, x1 = 141, icon = "icon_toolbar_back" },
    { id = "toc", x0 = 178, x1 = 393, icon = "icon_toolbar_catalog" },
    { id = "note", x0 = 396, x1 = 611, icon = "icon_toolbar_note" },
    { id = "progress", x0 = 614, x1 = 830, icon = "icon_toolbar_progress" },
    { id = "font", x0 = 833, x1 = 1049, icon = "icon_toolbar_font" },
    { id = "tts", x0 = 1049, x1 = 1264, icon = "icon_toolbar_tts" },
}""",
     """local BOTTOM_BUTTONS = {
    { id = "back", x0 = sx(0), x1 = sx(141), icon = "icon_toolbar_back" },
    { id = "toc", x0 = sx(178), x1 = sx(393), icon = "icon_toolbar_catalog" },
    { id = "note", x0 = sx(396), x1 = sx(611), icon = "icon_toolbar_note" },
    { id = "progress", x0 = sx(614), x1 = sx(830), icon = "icon_toolbar_progress" },
    { id = "font", x0 = sx(833), x1 = sx(1049), icon = "icon_toolbar_font" },
    { id = "tts", x0 = sx(1049), x1 = sx(1264), icon = "icon_toolbar_tts" },
}"""),
    ("local JOIN = { x = 54, y = 1090, w = 1156, h = 88 }",
     "local JOIN = { x = sx(54), y = sy(1090), w = sx(1156), h = sy(88) }"),
    ("local BUY = { member_y = 1381, member_h = 94, chapter_y = 1505, chapter_h = 89, auto_y = 1617 }",
     "local BUY = { member_y = sy(1381), member_h = sy(94), chapter_y = sy(1505), chapter_h = sy(89), auto_y = sy(1617) }"),
    ('table.insert(ops, T(632, 1315, "本书为付费会员卡可读", Theme.REGULAR, 30, nil, nil, "center"))',
     'table.insert(ops, T(sx(632), sy(1315), "本书为付费会员卡可读", Theme.REGULAR, 30, nil, nil, "center"))'),
    ('{ "rect", 45, BUY.member_y, 1174, BUY.member_h, Theme.BLACK }',
     '{ "rect", sx(45), BUY.member_y, sx(1174), BUY.member_h, Theme.BLACK }'),
    ("T(632, BUY.member_y + 19, hint, Theme.BOLD, 28, Theme.WHITE, nil, \"center\")",
     "T(sx(632), BUY.member_y + 19, hint, Theme.BOLD, 28, Theme.WHITE, nil, \"center\")"),
    ('{ "frame", 45, BUY.chapter_y, 1174, BUY.chapter_h, 3, Theme.LINE_GRAY, 22 }',
     '{ "frame", sx(45), BUY.chapter_y, sx(1174), BUY.chapter_h, 3, Theme.LINE_GRAY, 22 }'),
    ('{ "rect", 520, BUY.auto_y + 4, 24, 24, Theme.BLACK }',
     '{ "rect", sx(520), BUY.auto_y + 4, 24, 24, Theme.BLACK }'),
    ('{ "frame", 520, BUY.auto_y + 4, 24, 24, 3, Theme.BLACK, 12 }',
     '{ "frame", sx(520), BUY.auto_y + 4, 24, 24, 3, Theme.BLACK, 12 }'),
    ('{ "image", 52, 46, Theme.res("reading_back.svg"), 38, 38 }',
     '{ "image", sx(52), sy(46), Theme.res("reading_back.svg"), 38, 38 }'),
    ('{ "hline", 0, 135, self.dimen.w, 2, Blitbuffer.Color8(221) }',
     '{ "hline", 0, sy(135), self.dimen.w, 2, Blitbuffer.Color8(221) }'),
    ('{ "image", it.x, 64, Theme.res(icon), 53, 53 }',
     '{ "image", it.x, sy(64), Theme.res(icon), 53, 53 }'),
    ('{ "vline", 159, y0 + 31, 46, 1, Theme.LINE_GRAY }',
     '{ "vline", sx(159), y0 + 31, 46, 1, Theme.LINE_GRAY }'),
])

if fails:
    print("\n== 失败 ==")
    for f in fails:
        print(f)
    sys.exit(1)
print("\n全部补丁命中")
