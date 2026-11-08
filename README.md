# kindle-eink-dashboard

把旧款 Kindle（Paperwhite 3 / 7th gen 实测）改造成 **Mac 驱动的墨水屏看板**：
Mac 渲染页面 → 局域网推送 → Kindle 直写 framebuffer 显示。开机自动进入看板模式，
每 5 分钟自动刷新，其余时间深度睡眠省电。

> 本仓库同时是一个 [ZCode/Claude Skill](SKILL.md)——把整个改造过程中踩过的坑
> （LanguageBreak 越狱、eips 拉伸黑箱、framework 干扰、RTC 唤醒路径、OTA 拦截等）
> 整理成了可复用的操作指南。

## 效果

- 1072×1448 满屏、方向正确、灰度无变形
- 内容 = Mac 上的一个 HTML 页面（时钟/日期/天气/待办），改完 5 分钟自动上屏
- 显示层完全绕开 `eips`（其缩放行为是本项目最大的坑，详见 SKILL.md）

## 快速开始

### 0. 设备要求

- Kindle Paperwhite 3（其他 7 代+机型需自行验证）
- 固件 ≤ 5.16.2.1.1（LanguageBreak 越狱窗口，**切勿升级**）
- 已用 [LanguageBreak](https://github.com/notmarek/LanguageBreak) 越狱并安装 hotfix
  （流程与踩坑见 [SKILL.md 阶段一](SKILL.md)）

### 1. Mac 端

```bash
pip3 install Pillow numpy
# 用 Chrome 渲染看板并转换为 fb 原始帧
scripts/render_dashboard.sh
# 起服务（提供 dash.raw 下载）
python3 -m http.server 8899 --directory render
# 持续渲染（可选）
scripts/render_dashboard.sh --loop
```

### 2. Kindle 端

把 `scripts/emergency.sh` 拷到设备 USB 分区根目录（越狱 bridge 会在每次开机时
自动执行它，完成脚本部署 + 启动刷新循环），重启设备即可。

### 3. 自定义内容

编辑 `dashboard/dashboard.html`（时钟/日期/天气/待办都是普通 HTML），Mac 端
5 分钟内重新渲染，Kindle 下轮自动拉取上屏。

## 关键设计：为什么直写 framebuffer

PW3/5.16 上 `eips -g img.png` 显示图片时会把图**非等比拉伸到 1448×1448** 再写入
framebuffer，导致"方向正、垂直完整、水平放大裁切"的诡异画面；且 framework（系统 UI）
会被各种事件复活、反复改写 fb 状态。本仓库的做法：

1. Mac 端按 fb 真实格式（8bpp 灰度、行 stride 1088、1072×1448 逻辑坐标）生成原始帧
2. 设备端 `cat dash.raw > /dev/fb0` + `fbink -f -s` 触发刷新
3. 每轮刷新前 `initctl stop framework`，杜绝干扰

显示内容 100% 由 Mac 决定，确定性、可在线迭代。

## 文件

| 文件 | 说明 |
| --- | --- |
| [SKILL.md](SKILL.md) | 完整操作指南 + 踩坑速查表（AI skill / 人读皆可） |
| scripts/png2raw.py | PNG → fb raw 转换器 |
| scripts/emergency.sh | 设备端开机脚本（bridge 自动执行） |
| scripts/render_dashboard.sh | Mac 渲染管线 |
| dashboard/dashboard.html | 看板页面模板 |

## License

MIT
