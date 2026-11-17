---
name: kindle-eink-dashboard
description: 把旧款 Kindle（Paperwhite 3 / 7th gen 等）改造成 Mac 驱动的墨水屏看板 + 阅读器。覆盖 LanguageBreak 越狱、framebuffer 直写显示管线、eips 拉伸黑箱、OTA 拦截、KOReader/微信读书启动链（构建选型、libstdc++、坐标适配）与踩坑速查。当用户想把旧 Kindle 用作 e-ink dashboard / 副屏显示、装 KOReader / 微信读书、遇到 Kindle 越狱流程问题、eips 显示图片拉伸裁切方向错乱、framebuffer 直写 / cat /dev/fb0、Kindle OTA 自动更新拦截等问题时使用。
---

# 旧 Kindle 墨水屏看板：完整改造与踩坑指南

本指南来自一次完整的实战：2015 年 Kindle Paperwhite 3（固件 5.16.2.1.1）→ Mac 驱动的
墨水屏看板，全流程已验证。核心架构：

```
Mac（局域网 192.168.1.x）                     Kindle（PW3, 已越狱）
├─ dashboard.html 看板页面                    ├─ 开机 bridge 自动执行 emergency.sh
├─ Chrome 无头截图 → dash.png (1072×1448)     ├─ 每 5 分钟 RTC 唤醒
├─ png2raw.py 转换为 fb 原始帧 (8bpp)         ├─ xh 拉取 dash.raw
└─ HTTP :8899 静态服务                        ├─ cat > /dev/fb0 + fbink 刷新
                                              └─ 满屏灰度看板显示
```

设计决策：**显示层绕开 eips，Mac 端逐字节控制 framebuffer**。任何内容/方向/比例的
调整都在 Mac 端完成，设备端只是一个"哑显示终端"，调整纯在线生效，无需重启设备。

## 第 0 步：设备识别与红线

- USB：VID `0x1949`（Amazon）。序列号前缀查型号用
  [Mobileread 序列号 wiki](https://wiki.mobileread.com/wiki/Kindle_Serial_Numbers)。
- 固件版本读 USB 分区 `system/version.txt`。
- ⚠️ **红线：固件一旦升到 5.17+，LanguageBreak 永久失效**。动手前在 USB 分区根目录
  创建名为 `update.bin.tmp.partial` 的**文件夹**即可拦截 OTA 下载；同时尽量保持设备离线。

## 阶段一：越狱（LanguageBreak）

适用：固件 5.14.3–5.16.2.1.1 的 7 代及以后 Kindle。工具：
[notmarek/LanguageBreak](https://github.com/notmarek/LanguageBreak)（release 的
`LanguageBreak-*.tar.gz`，内含 hotfix）。官方流程见
[KindleModding Wiki](https://kindlemodding.org/jailbreaking/Legacy/LanguageBreak.html)，
以下是实测要点与坑。

1. **先备份**：USB 分区整个拷回电脑（demo 流程会清空设备）。
2. 确认无密码锁、飞行模式开启、根目录无 `.bin` 残留。
3. 搜索框输入 `;enter_demo` 回车 → 重启 → demo 初始化：跳过 WiFi、文本框随便填、
   Skip → Standard → Done。
4. 出现"展示机无内容/未连接网络 + 配置设备"锁屏后，用**秘密手势**解锁：
   **双指点屏幕右下角（"配置设备"按钮附近）→ 紧接单指从右向左横滑**。
   ⚠️ 网上流传的"右上角划"是错的；手势需连贯快速，可能试两三次。demo 初始化后要
   **等 3-5 分钟**配置真正完成，期间手势无效。
5. 主界面搜索框输入 `;demo` → 选 **Sideload Content（导入内容）** → 插 USB →
   把 `LanguageBreak/` 文件夹**内容**拷到设备根目录（含隐藏文件 `.demo/`）。
6. 回 `;demo` 菜单选 **Resell Device（销售设备）** → 确认 → "Press the Power Button"
   提示一出现**立刻重插 USB**，把 `LanguageBreak/` 内容**再拷一次**（部分固件此步会
   清空 /mnt/us，部分不会——写个监听脚本检测挂载并自动重拷最稳）。
7. 弹出、拔线、长按电源重启 → 语言选择界面出现 `P S E U D O T` 伪条目 = payload 就位。
8. 选**简体中文**（在 PSEUDOT 上方）→ 点屏幕中间出现的中文确认按钮 → 重启且右上角
   滚动日志 = 越狱成功。验证文件：根目录出现 `LanguageBreakRan` 和 `languagebreak_log`。
9. **Hotfix**：搜索框 `;uzb` 开 USB → 拷入 `Update_hotfix_languagebreak-zh-Hans-CN.bin`
   （与界面语言匹配）→ `;dsts` → Update Your Kindle。⚠️
   [issue #48](https://github.com/notmarek/LanguageBreak/issues/48)：**hotfix 常需安装
   两次**，第一次报 "Update Error" 是已知现象，重拷重装即可。

### 万能后门：bridge emergency.sh

越狱后 `mkk/bridge.sh` 每次开机（`framework_ready` 时）自动执行根目录的
`/mnt/us/emergency.sh`——这是"开机以 root 执行任意脚本"的通道。本项目的开机自启、
脚本远程部署全部走它。设备睡眠循环中 USB 会断开，部署脚本时用"后台监听挂载事件 +
捕获后立即写入并弹出"的原子方式最稳（见 `scripts/emergency.sh` 头部注释）。

## 阶段二：显示管线（本项目最大的坑）

### 设备显示硬件事实（PW3 / 5.16.2.1.1 实测，经 fb dump 验证）

- framebuffer：**1072×1448 竖向逻辑坐标，8bpp 灰度，行 stride 1088**
  （1072 可见 + 16 padding），fb rotation 3（270° CCW）。
- `libkh/bin/fbink` 是 **NOIMG 精简编译版**：没有图片显示能力，但 `-s`（纯刷新）可用。

### eips 的黑箱行为（多轮 fb dump 实测结论）

`eips -g img.png` 显示图片时会**把图片非等比拉伸到 1448×1448**（水平拉到 1448、垂直
拉到 1448）再写入 fb，可见区只显示拉伸图的左 74% 列。症状组合：

| 现象 | 本质 |
| --- | --- |
| 方向正、垂直完整、水平放大且右侧裁切 | eips 水平 1.35x 拉伸（1072→1448） |
| 内容躺倒（横持才正立） | 预旋转补偿后恰好 180°/360° 抵消 |
| 同样输入两次显示不同 | framework 活着，chrome 在改 fb rotation/覆盖内容 |

framework（chrome UI）会被 USB 插拔、进程崩溃、系统事件**反复复活**，且复活后改写
fb 状态——**一切显示实验必须在 framework 死亡、拔线状态下做**，否则数据全部被污染。

### 排查方法论（可直接复用）

1. **fb dump**：设备端 `cat /dev/fb0 > /mnt/us/fbdump.raw`（6.78 MB），Mac 端按
   `8bpp / stride 1088 / 1072×1448 / offset 0` 用 PIL 解析成 PNG 直接看。fb 里存的
   是什么就是什么，绕开一切猜测。
2. **带精确标记的测试图**（四角块 + 已知坐标竖线 + 刻度）比看板内容更适合做测量。
3. **数据点法**：喂不同尺寸输入（竖图/方图/横图）各 dump 一次，联立解出变换矩阵。
4. 每次 `eips` 显示后 dump，用 emergency.sh 通道自动化，避免反复插拔。

### 最终方案：绕开 eips，Mac 端逐字节直写 framebuffer

1. Mac 渲染 1072×1448 竖版 PNG（内容设计尺寸 = fb 逻辑坐标，无任何预旋转/补偿）。
2. `png2raw.py`：PNG → 8bpp 灰度 → 每行补 16 字节 0xFF padding → stride 1088 的 raw。
3. 设备端：`xh` 下载 raw → 校验字节数（1,575,424）→ `cat raw > /dev/fb0` →
   `fbink -f -s` 触发墨水屏全刷。
4. 内容/方向/比例全部由 Mac 端 PNG 决定；调整纯在线（改 HTML/转换参数，设备下轮
   自动拉取），无需重启。

## 阶段三：看板服务与电源

- **Mac 端**：`render_dashboard.sh`（Chrome 无头截图）+ `png2raw.py` + `python3 -m
  http.server 8899`，由每 5 分钟的循环脚本驱动。建议后续做成 LaunchAgent 开机自启。
- **设备端**：`emergency.sh` 开机部署最新脚本并启动循环：抓 raw → 写 fb → 刷新 →
  `next-wakeup` 算调度 → 睡眠。
- **RTC**：PW3 上 `/sys/devices/platform/mxc_rtc.0/wakeup_enable` **不存在**（原版
  kindle-dash 的路径），改用标准 Linux 接口
  `/sys/class/rtc/rtc0/wakealarm`（先写 0 清除再写 epoch 时间戳）。
- **framework 反复活**：USB 事件/崩溃都会 respawn 它并搅乱 fb。治本：dashboard 的
  **每轮刷新前**都执行 `initctl stop framework`（只靠开机杀一次不够）。
- **深睡断 USB**：设备 `echo mem` 睡眠后 USB 枚举断开，Mac 挂载会消失——部署要靠
  挂载事件监听抓窗口，或短按电源键唤醒。
- **FAT 写缓存**：设备侧写的文件（如日志）可能在睡眠前未落盘，Mac 挂载后看不到——
  不是丢失，等设备侧 sync。

## 阶段四：KOReader + 微信读书（PW3 实战全记录）

在 LanguageBreak+KHF 设备上跑通 KOReader 与 weread-kindle（微信读书客户端）的完整方案。
**社区文档空白点**：KUAL 在 5.14+ 废弃后，新固件老设备的 KOReader 启动入口只能走
bridge emergency.sh（KOL booklet 与 hotfix 版本接口不匹配，装不上）。

### 构建选型（最大的坑）

- PW3 这类经典框架设备（pillow/awesome）必须用 **`koreader-kindle-*.zip`**（legacy
  软浮点 target），**绝不能用 `koreader-kindlehf-*`**（那是 PW5/KS 新框架设备专用）。
- ⚠️ 症状极具迷惑性：装错构建时文件明明存在（ls 都能看到），shell 却报
  `./luajit: not found`——**ELF exec 失败（ABI 不符）在 shell 里就叫 "not found"**。
  之前的 `./reader.lua: not found` 同理（reader.lua 的 shebang 是 `#!./luajit`）。
- 部署布局：本体 `/mnt/us/koreader`，weread-kindle 在 `/mnt/us/weread`，`run.sh` 由
  `launcher/make-run.sh` 从 `koreader.sh` sed 生成（入口换成 main.lua）。
- macOS 拷贝后清理 AppleDouble：`find /mnt/us/koreader -name "._*" -delete`。

### 依赖三层检查（装完必做）

```bash
# 1) 构建平台：ARM 32 位 + 解释器 /lib/ld-linux.so.3
file koreader/luajit
# 2) libstdc++ 版本需求 vs 设备固件自带的（PW3 5.16 的偏旧）
strings -a koreader/common/rapidjson.so | grep -oE "GLIBCXX_3\.4\.[0-9]+" | sort -uV
# 3) glibc 需求上限（全树扫一遍，≤2.12 则任何 5.x 固件都安全）
for f in $(find koreader -name "*.so*"); do strings -a "$f" | grep -oE "GLIBC_2\.[0-9]+"; done | sort -uV | tail -1
```

**libstdc++ 坑**：新版 KOReader 的 `rapidjson.so` 需要 `GLIBCXX_3.4.29`，老固件自带的
libstdc++ 没有。解法：KOReader kindle 包 `libs/` 里**自带**新版 `libstdc++.so.6`
（3.4.33），启动前 `export LD_LIBRARY_PATH=/mnt/us/koreader/libs:$LD_LIBRARY_PATH`
即可。KOReader 前端自身对 rapidjson 失败会静默降级到 dkjson，但 weread-kindle 硬依赖
rapidjson，没有退路——所以库路径必须修。

### run.sh 入口的保险模式

koreader.sh 官方就把**自己、fbink、tar** 先 `cp` 到 `/var/tmp` 再 exec（vfat+fuse
规避模式）。本项目把同样的模式扩展到 luajit 入口行，并加了启动探针：

```sh
export LD_LIBRARY_PATH="/mnt/us/koreader/libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
cp -pf /mnt/us/koreader/luajit /var/tmp/luajit && chmod 777 /var/tmp/luajit
WEREAD_DIR=/mnt/us/weread /var/tmp/luajit /mnt/us/weread/main.lua "$@" >>crash.log 2>&1
```

⚠️ **bridge 的 upstart pre-start 是同步执行的**：emergency.sh 里必须把 run.sh
`nohup ... &` 后台化，否则 App 活着 = bridge job 卡死。

### 启动调试阶梯（四层日志，层层兜底）

| 层 | 文件 | 回答的问题 |
| --- | --- | --- |
| 1 | `/mnt/us/boot_trace.log` | emergency.sh 跑了吗？设备视角能看到哪些文件？标志测试结果？ |
| 2 | `/mnt/us/weread/boot.log` | run.sh 走到哪一步？`sh -x` 逐行轨迹 + 关键文件清单 |
| 3 | boot.log 探针段 | `./luajit -v` 直接 exec 测试（区分"构建错误"vs"fuse exec 问题"） |
| 4 | `/mnt/us/weread/crash.log` | luajit 本体的报错（只在该行执行后才有内容） |

crash.log 的重定向挂在 run.sh **最后一行**——入口行之前的任何死亡都不留痕迹，
必须靠 1-2 层。这是"crash.log 永远为空"谜题的正解。

### 模式标志、Wi-Fi 与 USB 纪律

- **默认开机进微信读书**；`weread_stop` 存在时才进看板，删除后恢复。`start_koread`
  保留为一次性兼容/强制进入入口，消费时同时清除 `weread_stop`。
- 启动保护：3 分钟窗口内最多拉起 4 次，状态存 `/var/local/weread-launch.guard`，
  防止启动异常形成反复重启。
- 开机主动 `wirelessEnable 1`。App 内 `weread/wifi.lua` 在请求失败后检查
  `com.lab126.wifid cmState`，未连接时打开无线，已打开但未关联则先关再开；
  跨请求 12 秒防抖，最多等待 45 秒。息屏天气先等 Wi-Fi，失败 60 秒重试。
- Mac 端写标志或脚本后必须 `sync` 再 `diskutil eject`。
- ⚠️ **重启前必须拔线**。插线状态下重启，开机早期 USBMS 接管 /mnt/us，设备侧
  `-f /mnt/us/emergency.sh` 直接失明，bridge 落回默认路径（偶发，时序相关）。
- 微信读书运行中插 USB 看不到卷 = 设计使然（App SIGSTOP 了 volumd 防打扰），
  正常退出 App 或重启即恢复。
- PW3 屏幕的 e-ink 全屏白闪 = 完整刷新（真重启的标志）；看板 fbink 刷新也会闪，
  别把刷新闪当重启。

### PW3 坐标适配（1264×1680 → 1072×1448）

weread-kindle 界面按官方墨水屏版（1264×1680）逐像素摆放，PW3 上整体右偏 ~96px 且
部分控件出屏。适配原则：

- **逐文件缩放常量**：`sx(v)=floor(v*SW/1264+0.5)`、`sy(v)=floor(v*SH/1680+0.5)`，
  绘制与点按热区用同一缩放值（自然一致）。
- ❌ 不能在 canvas.lua 做全局变换：阅读页划线/笔记的坐标来自 crengine 排版引擎
  （设备空间），与设计空间的界面坐标混在同一画布，全局缩放会错位。
- 已适配 9 个文件（登录/底栏/书预览/目录/导入引导/设置/详情/划线评论/阅读页工具栏），
  见 `render/weread-pw3/` 副本与 `scripts/patch_pw3_layout.py`（每处替换带唯一性断言）。
- 已知残留：readerview 的弹出面板（进度/字体/更多）内部仍是设计坐标——自洽可用
  （画和点一致），只是整体略偏，后续按需补。
- 登录态存 `/mnt/us/weread/session.json`，重启/适配不丢。

## 踩坑速查表

| 症状 | 原因 | 解法 |
| --- | --- | --- |
| demo 锁屏手势无效 | 配置未完成 / 手势错误 | 等 3-5 分钟；双指右下+左滑 |
| 越狱后部分组件异常、KUAL 不工作 | hotfix 只装了一次 | 重拷 hotfix 再装一次 |
| KUAL 不出现在图书馆 | KUAL 在 5.14.3+ 已废弃 | 用 bridge emergency.sh / scriptlet，别装 KUAL |
| eips 显示放大裁切 | 非等比拉伸到 1448×1448 | 绕开 eips，fb 直写（本仓库方案） |
| 同样脚本显示时好时坏 | framework 复活改 fb 状态 | 每轮刷新前 `initctl stop framework` |
| 插线后设备不挂载 | mem 睡眠断 USB | 拔插重枚举 / 短按电源键唤醒 |
| Mac 看不到设备侧新写的文件 | FAT 写缓存未落盘 | 非丢失，设备侧 sync 后可见 |
| 设备刷新几次后永久黑屏 | RTC 闹钟路径不存在睡死 | 用 `/sys/class/rtc/rtc0/wakealarm` |
| 重启后看板没自启 | emergency.sh 缺失/未执行 | 确认根目录 emergency.sh 可执行 |
| 二进制存在却报 `./luajit: not found` | ELF exec 失败（装错构建 ABI），shell 误报 not found | 换 koreader-kindle 版（PW3 忌 kindlehf） |
| crash.log 报 GLIBCXX_3.4.29 not found | 固件 libstdc++ 太老，rapidjson 加载失败 | `LD_LIBRARY_PATH` 指向 koreader/libs（自带新版） |
| crash.log 永远为空 | run.sh 死在入口行之前，重定向还没挂上 | emergency.sh 用 `sh -x` 记 boot.log |
| 重启没消费标志/看板照常启动 | 插线状态重启，USBMS 接管 /mnt/us | eject 后**拔线**再长按重启 |
| 重启后总是进入看板 | 新版脚本检测到 weread_stop | 删除 weread_stop，sync/eject 后拔线重启 |
| 微信读书断网后一直请求失败 | awesome 停止后无线未自动重连 | weread/wifi.lua 主动 wirelessEnable，45 秒窗口重试 |
| 界面整体右偏/控件出屏 | weread 按 1264×1680 官方稿绝对定位 | 按屏比例缩放（`scripts/patch_pw3_layout.py`） |
| 设备各种写失败/白屏/应用猝死 | framework 崩溃风暴：每个 core ~196MB 塞满 3GB 分区 | 删 `/mnt/us/*.core`；emergency.sh 里 core_pattern → /dev/null |
| App 运行中插 USB Mac 看不到卷 | App SIGSTOP volumd（防打扰设计） | 正常退出 App 或重启 |
| KOReader 本体"部署了"却起不来 | 只装了 extensions/koreader（KUAL 壳），本体缺失 | 确认 `/mnt/us/koreader/luajit` 等实体文件在 |
| 屏幕出现 Collecting Debug Info | framework 进程崩溃 | 已知现象，点 CLOSE 继续 |

## 仓库文件

- `scripts/png2raw.py` — PNG → fb raw 转换（8bpp、stride 1088、字节数校验）
- `scripts/emergency.sh` — 设备端开机脚本（默认微信读书、看板回退、启动保护）
- `scripts/render_dashboard.sh` — Mac 端渲染管线（Chrome 截图 + 转换）
- `scripts/patch_pw3_layout.py` — weread 界面 PW3 坐标适配补丁（唯一性断言）
- `scripts/kindle-flag.sh` — 标志设置/清除工具（自动 sync，防 FAT 回滚/丢写）
- `render/final_emergency.sh` — 与 scripts/emergency.sh 同步的兼容部署副本
- `render/weread-pw3/` — weread PW3 界面、Wi-Fi 重连与天气息屏 Lua 部署源
- `dashboard/dashboard.html` — 看板页面模板（时钟/日期/天气/待办，e-ink 高对比设计）
- `downloads/` — 安装包与上游源码（koreader-kindle/kindlehf、weread-kindle、staging）

## 依赖

- Mac：Google Chrome、Python3 + Pillow + numpy、`gh`/curl
- 设备：LanguageBreak 越狱 + hotfix（自带 mkk bridge、libkh/bin/fbink、xh 依赖）
