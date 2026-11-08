---
name: kindle-eink-dashboard
description: 把旧款 Kindle（Paperwhite 3 / 7th gen 等）改造成 Mac 驱动的墨水屏看板。覆盖 LanguageBreak 越狱、framebuffer 直写显示管线、eips 拉伸黑箱、OTA 拦截与踩坑速查。当用户想把旧 Kindle 用作 e-ink dashboard / 副屏显示、遇到 Kindle 越狱流程问题、eips 显示图片拉伸裁切方向错乱、framebuffer 直写 / cat /dev/fb0、Kindle OTA 自动更新拦截等问题时使用。
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
| 屏幕出现 Collecting Debug Info | framework 进程崩溃 | 已知现象，点 CLOSE 继续 |

## 仓库文件

- `scripts/png2raw.py` — PNG → fb raw 转换（8bpp、stride 1088、字节数校验）
- `scripts/emergency.sh` — 设备端开机脚本模板（部署 + 启动 + 刷新循环 + RTC 睡眠）
- `scripts/render_dashboard.sh` — Mac 端渲染管线（Chrome 截图 + 转换）
- `dashboard/dashboard.html` — 看板页面模板（时钟/日期/天气/待办，e-ink 高对比设计）

## 依赖

- Mac：Google Chrome、Python3 + Pillow + numpy、`gh`/curl
- 设备：LanguageBreak 越狱 + hotfix（自带 mkk bridge、libkh/bin/fbink、xh 依赖）
