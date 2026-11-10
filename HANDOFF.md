# 工作交接 — Kindle PW3 墨水屏看板 + KOReader/微信读书

> 会话日期：2026-11-09 ~ 11-11。本文件是**下一会话的工作交接**，配套
> [SKILL.md](SKILL.md)（通用踩坑指南）阅读。设备序列号 G090KB03702608LE
> （Kindle Paperwhite 3 / 7th gen / 白色 WiFi，固件 5.16.2.1.1，**切勿升级**）。

## 当前状态总览

### ✅ 已完成并验证
- **看板模式**：LanguageBreak 越狱 + hotfix + 直写 framebuffer 显示管线
  （Mac 渲染 1072×1448 竖版 → 8bpp raw → `cat > /dev/fb0` → `fbink -f -s`），
  满屏、方向正、无变形。**Mac 重启后需重新拉起服务**（见"待办"）。
- **北京真实天气**：Open-Meteo API（无需密钥），`scripts/fetch_weather.py`。
- **浏览器实时预览**：`http://192.168.1.210:8899/preview.html`（60s 自动同步）。
- GitHub 已开源：本仓库。

### ⚠️ 当前设备状态（最后快照）
- `emergency.sh` = 最新版（含 `start_koread` 分支 + nosleep 检测 + sync 修复）✅
- `weread/run.sh` = cd 修复版 ✅（`cd /mnt/us/koreader` 已写入主循环前）
- `weread.koplugin` v1.7.0 = 已部署到 `koreader/plugins/` ✅
- 标志：`start_weread`/`dashboard_stop` 已清；`start_koread`/`nosleep` 在设备上
  （最后快照时在线）——**下次插线先检查并按需清理**
- `weread/crash.log` = 空（main.lua 从未执行——见"卡点"）
- 设备屏幕：最后已知为"天气页残影"（e-ink 残留，实际状态未知）

## 🎯 卡点：KOReader 从未真正启动（下一步的第一件事）

**现象**：`start_koread` 分支执行（标志被消费），但 KOReader 本体从未显示，
`weread/crash.log` 始终为空（main.lua 从未执行）。

**已定位的根因链**（修复已部署但**未经真重启验证**——这是关键）：
1. `emergency.sh` 的 start_koread 分支原本调 `koreader/koreader.sh`（KOReader
   官方脚本）→ 它的 334 行 `ko_update_check` 用 `./reader.lua` 相对路径，在
   bridge 的 CWD（/）下崩 → `./reader.lua: not found`（crash.log 报过一次）。
2. **修复**：分支已改为调 `weread/run.sh`（定制启动器，内含
   `cd /mnt/us/koreader || exit 1` 修复 + luajit main.lua 入口）——**已部署**。
3. ⚠️ **但用户端很可能从未做过一次"真重启"**：多次"重启"实为 mem 唤醒
   （电源键短按），emergency.sh 从未在标志部署后真正执行。**验证方法**：
   长按电源 15~30 秒硬重启，屏幕会**全黑→全白闪烁**（e-ink 完整刷新）。
4. 附加教训：`start_weread` 轮触发过**整机重启死循环**——weread 启动分支里
   `initctl stop framework` 在 PW3 上导致图形系统异常循环；且标志 rm 后未
   `sync` 被 FAT 回滚复活。**两处均已在最新脚本修复**（weread 分支已删除，
   改为 KOReader 直启；rm 后强制 sync）。

### 下次继续的第一步
1. 插线 → 检查 `start_koread`/`nosleep` 标志，清理为 `start_koread` 单标志
2. **长按电源 15~30 秒硬重启**（确认 e-ink 全屏刷新 = 真重启）
3. 等 1 分钟 → 插线读 `weread/crash.log`（这次必有内容）：
   - main.lua 报错 → 按报错修（多为 weread-kindle 的 Oasis3 坐标硬编码，
     见 `weread/weread/bookpreviewview.lua:22` 的 `W,H = 1264,1680`，需适配
     PW3 的 1072×1448；比例接近 0.752 vs 0.740，适配可行性高）
   - KOReader 界面出现 → 菜单 → 工具 → **微信读书**（weread.koplugin
     v1.7.0 已装）→ 微信扫码登录 → 完成
4. 若 KOReader 本体崩 → 读 `koreader/crash.log`；kindlehf 版若异常可换
   `downloads/koreader-kindle-v2026.07.1.zip`（标准版，已在本地）重试

## 关键机制（精要）

- **bridge emergency.sh**：`mkk/bridge.sh` 每次开机（framework_ready）以 root
  执行 `/mnt/us/emergency.sh`——一切开机逻辑的入口。修改它=修改开机行为。
- **标志开关模式**：Mac 端在 USB 卷上 `touch/rm` 标志文件，emergency.sh 检测
  分支。⚠️ **rm 后必须 sync**（否则 FAT 回滚，标志复活——曾导致重启死循环）。
- **nosleep**：`/mnt/us/nosleep` 存在时设备浅睡不断 USB（大文件部署窗口）。
- **fb 直写**：8bpp 灰度、stride 1088（1072 可见+16 padding）、1072×1448
  竖向逻辑坐标。`eips -g` 会把图非等比拉伸到 1448×1448（勿用，已绕开）。
- **scriptlet 不可用**：LanguageBreak 的 hotfix（KHF）不含 Universal Hotfix
  的 SH_Integration——documents 里的 .sh 不会显示为书。KOL booklet 安装包
  与 hotfix 版本接口不匹配（update error 2）——启动入口只能走 emergency.sh。

## 待办（按优先级）

1. [ ] **真重启验证 start_koread → KOReader → 微信读书**（见上）
2. [ ] weread 界面 PW3 坐标适配（若错位）：改 `weread/weread/*.lua` 的
       硬编码坐标（集中在 bookpreviewview/readerview 等，比例系数约 0.848）
3. [ ] **LaunchAgent**：Mac 重启后自动拉起渲染循环 + HTTP 服务
       （`scripts/render_dashboard.sh --loop` + `http.server 8899`）
4. [ ] 正式刷新节奏：设备 `dashboard/local/env.sh` 的 `REFRESH_SCHEDULE`
       （现测试值 `*/5 * * * *`，建议改 `"0,30 8-22 * * *"`）
5. [ ] weread 双模式切换打磨（start_weread/dashboard_stop 标志的 UI 化）
6. [ ] KOReader 验证成功后：把 LanguageBreak+KHF 设备的 KOReader 启动方案
       补进 SKILL.md（社区文档空白点）

## 文件地图

```
设备（/mnt/us，即 USB 卷根）：
├── emergency.sh          # 开机入口（bridge 执行）——最新版在本仓库 render/
├── koreader/             # KOReader 本体（kindlehf v2026.07.1）
│   └── plugins/weread.koplugin/   # 微信读书插件 v1.7.0
├── weread/               # 微信读书客户端（main.lua + run.sh + weread/）
├── weread/crash.log      # main.lua 的崩溃日志（下次验证关键证据）
├── dashboard/            # 看板（env.sh 刷新节奏、local/fetch 脚本）
├── nosleep / start_koread / dashboard_stop   # 标志开关（按需清理）
└── update.bin.tmp.partial/          # OTA 拦截（⚠️ 删了会失守越狱）

Mac（工具/kindle-eink-dashboard/）：
├── render/               # dashboard.html、dash.png/raw、weread.koplugin
├── scripts/              # png2raw、fetch_weather、render_dashboard、emergency.sh 模板
├── downloads/            # 全部安装包（KOReader 两版、weread-kindle 源码、staging/）
└── （老目录 工具/kindle-jailbreak/ 有 fb dump 分析等历史工件）
```

## 服务运维（Mac 侧）

```bash
# 渲染循环（每 5 分钟：拉天气 → 截图 → 转 raw）
scripts/render_dashboard.sh --loop
# HTTP 服务（设备从这里拉 raw）
python3 -m http.server 8899 --directory render
# 端口冲突时清理
pkill -f "http.server 8899"; pkill -f render_dashboard.sh
```
