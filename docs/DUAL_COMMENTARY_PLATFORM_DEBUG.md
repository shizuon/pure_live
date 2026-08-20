# 双流解说模式：平台调试与移植说明

## 当前实现基线

- 上游基线：`liuchuancong/pure_live` `master`，提交 `59d4158885050428bd72b3f837ea27ddeccc2157`。
- 应用版本：`2.3.0+4069`。
- Flutter：`3.47.0`。
- 平台状态：macOS 为正式验证目标；Windows、iOS/iPadOS 已开放实验入口，Android 仍保持关闭。
- 工作模式：A 播放主画面，B 提供解说声音；B 的低清画面仅在校准窗口显示。

当前功能包括：

- A、B 两个独立播放器槽位，互不覆盖播放器和房间状态。
- B 默认从最低清晰度开始，逐线路、逐清晰度尝试。
- B 就绪前继续播放 A 原声；B 缓冲或失败时恢复 A 原声。
- `±10ms`、`±100ms`、`±500ms` 调整，范围 `-30s` 到 `+30s`。
- macOS/Windows 使用 `[`、`]` 调整 `100ms`，按住 Option/Alt 调整 `10ms`，按住 Shift 调整 `500ms`。
- 校准完成后关闭 B 视频轨；“再次校准”会重新启用 B 画面。
- 可选 A 或 B 的弹幕；B 弹幕复用正向音频偏移，负偏移时立即显示。
- 弹幕断线后固定每 15 秒重连，手动关闭或离开房间后停止重连。
- 双流期间禁止录制；仅音频模式与双流模式互斥。
- 虎牙 FLV/HLS 使用各自匹配的令牌和扩展名，虎牙 CDN 地址升级为 HTTPS。
- macOS 禁用 Impeller 宽色域合成，固定使用 Skia Metal 的 sRGB/BGRA8 表面，避免 HDR 显示器窗口模式下双视频纹理损坏旁侧弹幕 UI；MediaKit 的 `auto-copy` 解码保持不变。

## 本轮构建与自动化验证（2026-08-20）

- `flutter analyze --no-pub`：通过，无静态检查问题。
- `flutter test --no-pub`：177 项全部通过，覆盖 10ms 偏移显示/执行、平台白名单、双播放器生命周期、弹幕延迟/重连和音频模式切换。
- macOS Release：构建通过，版本 `2.3.0+4069`，主程序同时包含 `arm64` 与 `x86_64`，应用内 `FLTEnableImpeller=false` 已核验，ad-hoc 深度签名验证通过。
- iOS Release：在非 FileProvider 临时目录执行 `flutter build ios --release --no-codesign --no-pub` 成功，生成 `arm64` 设备版 `Runner.app`。这证明代码和原生依赖可编译，不等同于真机行为验收。
- Windows：功能入口、控制器和快捷键已迁移，平台白名单单测通过；macOS 无法生成或运行 Windows 桌面包，仍需在 Windows 机器执行下方构建及长时间播放清单。

如果工程位于 macOS 的 Documents/FileProvider 目录，系统可能给 `.app` 或 `.framework` 自动附加 Finder 扩展属性，导致 Xcode 临时签名报告 `resource fork ... not allowed`。这是构建目录问题，不是播放器代码错误；将验证副本放到 `/private/tmp` 或其他非同步目录即可避免。

## Windows 调试清单

### 1. 功能入口

入口已通过 `CommentaryPlatformSupport` 显式开放 Windows，解说按钮、状态条、B 校准画面和桌面快捷键共用同一白名单。Android 没有被顺带开放。

### 2. 构建环境

1. 安装项目 `.fvmrc` 指定的 Flutter `3.47.0`。
2. 启用 Windows Desktop，并安装与 Flutter 版本兼容的 Visual Studio C++ Desktop 工具链。
3. 在仓库根目录执行依赖解析、静态检查和 Windows Release 构建。
4. 首次构建前确认 MediaKit Windows 原生库已经解析完成。

建议命令：

```powershell
fvm flutter pub get
fvm flutter analyze
fvm flutter test
fvm flutter build windows --release
```

### 3. 优先验证项

1. A、B 能否同时创建两个 MediaKit/MPV 实例。
2. B 校准窗口是否能稳定渲染，关闭校准后 B 视频轨是否停止解码但音频不断。
3. Windows 音量滑块是否只控制 B，退出或 B 失败后 A 是否恢复原保存音量。
4. 空格、媒体键、刷新和悬浮窗关闭是否同时控制两路。
5. A 切清晰度或线路时，B 和当前偏移是否保留。
6. 反复进入、退出双流 20 次，任务管理器中不能持续增加播放器、网络连接或音频输出。
7. 虎牙线路 1～6 分别播放至少 10 分钟，记录 FLV/HLS、编码格式、错误文本和发生时间。

Windows 需要确认不同键盘布局下 `LogicalKeyboardKey.bracketLeft/right` 以及 Alt 修饰键都能收到事件。

### 4. Windows 日志采集

复现时至少保存：

- A、B 的平台、房间号、清晰度和线路序号。
- 最终播放 URL 的协议、主机、扩展名；不要公开完整鉴权查询参数。
- MediaKit/MPV 的错误分类和原始错误文本。
- A、B 的 buffering、playing、position 状态变化时间。
- 双流状态、用户偏移、漂移纠正速率以及是否发生重连。

## iPad / iOS 可行性

结论：Dart/MediaKit 共用实现已开放 iOS/iPadOS 实验入口，但在真机完成资源、音频会话和 PiP 验证前不作为正式发布目标。

### 可复用部分

- 双播放器槽位、直播源解析、偏移数学、漂移判断、B 重连状态机均为 Dart 层逻辑，可直接复用。
- MediaKit 已是项目的 iOS 播放后端，A/B 两个播放器的基本结构不需要改成 FFmpeg 合流。
- A/B 弹幕选择和延迟队列可直接复用。
- 触控同步面板可复用；Mac 键盘快捷键不开放。

### 主要风险

1. iOS 音频会话：两个播放器必须共享正确的音频会话，来电、耳机断开、锁屏和控制中心操作要同时控制两路。
2. 硬件解码资源：iPad 通常余量较大，旧 iPhone 同时解码两个视频可能触发温升、掉帧或系统终止。
3. 后台与锁屏：双视频解码不应在后台持续；进入后台时应关闭 B 视频轨，并根据产品策略暂停 A 视频。
4. PiP：系统 PiP 只能以 A 为主画面；B 只能作为应用内音频来源，不能创建第二个系统 PiP。
5. App Store 合规：功能不保存、不重新分发组合内容；仍需复核直播平台条款和后台音频声明。

### 建议的 iOS 分阶段方案

1. iPadOS 前台实验：仅横屏、仅应用前台、无系统 PiP。
2. 验证双流 30 分钟的温度、内存、掉帧、音画漂移和音频中断恢复。
3. 校准完成后强制关闭 B 视频轨；再次校准时临时恢复。
4. 再验证 iPad PiP、锁屏和控制中心。
5. 最后在三档 iPhone 设备上验证并决定是否开放手机入口。

## 回归验收

- B 未就绪、缓冲或失败时始终能听到 A。
- B 稳定后 A 静音，退出双流后 A 恢复进入双流前的音量。
- 用户可多次打开 B 校准画面并以 10ms 精度调整，`±10ms` 不能显示成 `0.0s`。
- 正偏移让 B 声音和 B 弹幕延后；负偏移让 B 声音提前，弹幕立即显示。
- 双流中不能启动录制，也不能切到仅音频模式。
- 离开房间、关闭悬浮窗或退出应用后没有 B 残留声音。
- 弹幕连接断开后每 15 秒重试，手动关闭后不再重试。
- HDR 显示器在窗口模式同时显示 A、B 视频和右侧弹幕列表时，不出现黄蓝扫描线、黑块或文字缓存损坏；全屏行为不回退。
