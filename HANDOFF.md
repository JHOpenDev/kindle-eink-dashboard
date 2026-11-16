# 工作交接 — Kindle PW3 墨水屏看板 + KOReader/微信读书

> 更新：2026-11-11 晚。设备序列号 G090KB03702608LE（Kindle Paperwhite 3 / 7th gen /
> 白色 WiFi，固件 5.16.2.1.1，**切勿升级**）。本文件与 [SKILL.md](SKILL.md)（通用踩坑
> 指南，已含本次全部经验）配套阅读。

## ✅ 当前状态：双模式全部可用（2026-11-11 全部验证）

### 看板模式（默认开机）
开机 bridge → emergency.sh → dashboard/dash.sh 循环：拉天气 → Mac 拉 dash.raw →
写 fb → 刷新 → RTC 睡眠。**Mac 重启后需重新拉起服务**（LaunchAgent 仍未做）：
```bash
scripts/render_dashboard.sh --loop          # 渲染循环
python3 -m http.server 8899 --bind 0.0.0.0  # HTTP 服务
pkill -f "http.server 8899"; pkill -f render_dashboard.sh   # 端口冲突清理
```

### 微信读书模式（start_koread 标志）
Mac 在卷根 `touch start_koread` + sync + eject + **拔线** + 长按重启 → emergency.sh
消费标志 → `weread/run.sh`（后台化）→ KOReader kindle 版底座 → 微信读书 App。
**已登录**（session.json 持久化），界面已做 PW3 坐标适配，验证完美。
工具：`scripts/kindle-flag.sh set start_koread`（卷挂载时）。

### 本次修复的四个死因（全部实锤，详见 SKILL.md 阶段四）
1. **KOReader 本体从未上机**（extensions/koreader 只是 KUAL 壳）→ 拷入 kindle 版
2. **装错构建**：kindlehf（PW5 专用）在 PW3 上 exec 失败，shell 误报 `./luajit: not
   found` → 换 koreader-kindle v2026.07.1
3. **rapidjson 需 GLIBCXX_3.4.29**，固件 libstdc++ 太老 → run.sh 里
   `LD_LIBRARY_PATH=/mnt/us/koreader/libs`（包内自带 3.4.33）
4. **界面按 1264×1680 设计**，PW3 右偏/出屏 → 9 文件 ~120 处坐标按屏比例缩放
   （`render/weread-pw3/` + `scripts/patch_pw3_layout.py`）

### 关键机制备忘
- **core 转储事故（2026-11-16）**：framework（KPPMainAppV2）崩溃时每个 core ~196MB，
  15 个塞满 3GB 分区 → 全系统写失败（白屏/应用猝死/日志 0 字节）。emergency.sh 已加
  `core_pattern → /dev/null` 内核防线；若再遇到满盘先查 `/mnt/us/*.core`。
- **dash.sh 防挂死**：启动时先画磁盘上最后一张看板（白屏急救），initctl/lipc/电量计
  全部带 timeout 降级（异常状态下这些调用可能永久阻塞）。
- **自定义息屏图**：`/mnt/us/weread/sleep.png` 存在则优先于书籍封面快照
  （app.lua hookScreensaver 已打补丁）。换图 = 替换该文件（1072×1448 PNG）。
  息屏唤醒只认电源键（无滑动解锁手势）；偶尔需按两次是 KOReader 唤醒竞态。
- **标志是一次性的**：emergency.sh 消费后 rm+sync（防重启死循环）。重试必须重设。
- **重启前必须拔线**：插线重启时 USBMS 接管 /mnt/us，emergency.sh 设备侧"不存在"
  （偶发但真实发生过）。
- **调试四层日志**：boot_trace.log（设备视角）→ weread/boot.log（sh -x 轨迹+探针）→
  crash.log（luajit 报错）。定位死点全靠它们，勿靠猜。
- **bridge pre-start 同步执行**：emergency.sh 里的长任务必须后台化。
- **App 运行中插 USB 无卷** = 设计使然（volumd 被 SIGSTOP），退出 App 即恢复。
- `update.bin.tmp.partial/` 文件夹 = OTA 拦截，**删了会失守越狱**。

## 待办（按优先级）

1. [ ] **LaunchAgent**：Mac 重启后自动拉起 `render_dashboard.sh --loop` + `http.server
       8899`（看板模式目前依赖手动）
2. [ ] 正式刷新节奏：`dashboard/local/env.sh` 的 `REFRESH_SCHEDULE`（现 `*/5` 测试值，
       建议 `"0,30 8-22 * * *"`）
3. [ ] 微信读书弹出面板（阅读页进度/字体/更多面板）内部仍是 1264 设计坐标——自洽可用
       但整体略偏，按需补（readerview.lua 的 SLIDERS/FONT_GRID/MORE/INDENT 表 +
       panelY 函数）
4. [ ] weread 双模式切换打磨（start_weread/dashboard_stop 标志 UI 化）
5. [ ] 稳定后可移除 emergency.sh 顶部的 boot_trace 段（省一次文件写入）
6. [ ] 考虑把 render/weread-pw3 与 downloads/weread-kindle 上游做 git 管理便于升级

## 文件地图

```
设备（/mnt/us，即 USB 卷根）：
├── emergency.sh          # v3：boot_trace 飞行记录仪 + 一次性标志分支（仓库 render/final_emergency.sh）
├── boot_trace.log        # 每次开机的设备视角记录（调试用，可删）
├── koreader/             # KOReader kindle 版 v2026.07.1 本体（1029 文件）
│   ├── libs/libstdc++.so.6   # 自带新版（3.4.33），LD_LIBRARY_PATH 指向这里
│   └── plugins/weread.koplugin/  # 微信读书 KOReader 插件 v1.7.0（备用，App 模式不用它）
├── weread/               # 微信读书客户端
│   ├── run.sh            # koreader.sh 派生 + cd 修复 + LD_LIBRARY_PATH + /var/tmp luajit + 探针
│   ├── boot.log          # 启动轨迹（sh -x）
│   ├── crash.log         # luajit 报错
│   ├── session.json      # 登录态（勿删）
│   └── weread/*.lua      # 界面（已刷成 PW3 适配版，源在仓库 render/weread-pw3/）
├── dashboard/            # 看板（env.sh 调度、logs/dash.log）
├── nosleep / start_koread  # 标志（nosleep=浅睡不断 USB；start_koread=一次性）
└── update.bin.tmp.partial/  # OTA 拦截（⚠️ 删了会失守越狱）

Mac（工具/kindle-eink-dashboard/）：
├── render/
│   ├── final_emergency.sh    # 设备 emergency.sh 的部署源（v3）
│   ├── weread-pw3/           # PW3 适配版界面 Lua（部署源）
│   └── weread.koplugin/      # 插件 v1.7.0
├── scripts/
│   ├── patch_pw3_layout.py   # 坐标适配补丁（唯一性断言，可重放）
│   ├── kindle-flag.sh        # 标志工具（自动 sync）
│   └── emergency.sh          # 纯看板版模板（历史）
└── downloads/                # 安装包（koreader-kindle ←用这个、weread-kindle 源码、staging）
```
