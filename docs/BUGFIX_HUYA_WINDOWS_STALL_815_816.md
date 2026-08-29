# 虎牙 Windows 数分钟后停止：Issue 815 / 816

## 范围与来源

- Issue：[815](https://github.com/liuchuancong/pure_live/issues/815)、[816](https://github.com/liuchuancong/pure_live/issues/816)
- 报告版本：`3.0.7+4095`
- 平台：Windows x64
- 最后正常版本：`2.9.8`
- 当前上游冻结点：`fac506c76085a547af06ba8541473a836e108c16`
- 来源分类：`upstream-existing`
- 当前结论：源码回归已修复，仍需 Windows 线路 1～6 各 30 分钟实机验证后才能关闭 Issue。

## 最短复现与证据

进入任意虎牙直播间等待约 3～5 分钟，画面停止，独立 WebSocket 弹幕仍继续。报告者和补充测试显示线路存在明显差异：4～6 正常，3 大致正常，1 直接失败，2 报 network error 后停止。

2026-08-29 的脱敏接口检查确认在线房间会返回 AL、TX、HS 三组 CDN，每组同时包含 FLV/HLS 页面签名；CDN 基址仍可能为 HTTP。Mac 上 WUP/CDN 探测会长时间无响应，因此外部探测只作为环境证据，不代替 Windows MediaKit 长播。

## 第一个错误状态

`82aa7a747c1560a52ed9fff8a52ab8cf3bd1411c` 位于 `2.9.8` 与 `3.0.7` 之间。它把虎牙播放从“原样使用 CDN 页面签名”改成“对每个页面签名重新计算 seqid/wsSecret”。该变化原本用于允许播放与录制并发，却同时改变了普通播放的签名契约；`3.0.7` 是首个被报告异常的版本。

同一版本区间还删除了 Windows `_WindowsViewportSizedVideo`。旧实现按可见物理像素限制 BGRA 纹理尺寸，并以 180ms 去抖窗口调整；新实现只设置 Flutter `aspectRatio`，不再限制原生纹理。这可以造成“解码/网络仍在，但窗口纹理不再更新”的第二种冻结表现。

`force-seekable=yes` 和当时的短探测属性在 `2.9.8` 已存在，不是版本间第一个错误状态，本次不把它们当成根因，也不随意更改。

## 修复设计

### 虎牙签名

1. 采用最新上游 WUP 新签名方向，但把默认 60000 秒连接等待改为 2 秒，并增加 3 秒整体硬超时。
2. 同一 stream 的并发 WUP 请求合并，成功签名缓存 2 分钟。
3. 失败后冷却 30 秒，期间不重复阻塞；直接使用对应协议的页面签名。
4. 只有 WUP 新签名模板会重新计算；页面签名恢复 `2.9.8` 原样语义。
5. FLV 使用 FLV 签名和 `.flv`，HLS 使用 HLS 签名和 `.m3u8`。
6. 只把 `*.huya.com` 的 HTTP CDN 升级为 HTTPS；无关主机不改写。
7. codec/ratio 统一替换而非重复追加；原画删除旧 ratio。
8. 保留用户显式线路，播放失败不自动切换到 4～6。

### Windows 纹理

恢复最新版接口兼容的有界纹理包装：保留当前 `BoxFit`、宽高同一 decoder event 和 MediaKit 生命周期，仅在 Windows 调用 `VideoController.setSize()`；尺寸不超过视频源，保持偶数像素，窗口拖动以 180ms 去抖，dispose 取消 Timer 和两个订阅。

## 自动化证据

- 虎牙 FLV/HLS 协议、签名、HTTPS、codec/ratio。
- WUP 并发请求合并、2 分钟成功缓存、失败冷却和页面签名原样后备。
- Windows 输出尺寸：物理像素、源尺寸上限、宽高比和偶数像素。
- 双流同步、10ms/100ms/500ms、A/B 弹幕源延迟、15 秒重连和 HDR 修复作为相邻模式回归。

## Windows 验证与回滚

每条线路至少播放 30 分钟，同时记录协议、CDN 主机（不含查询参数）、playing/buffering/position、原始 MediaKit 错误和窗口/全屏状态。普通窗口与全屏都需要覆盖，以区分输入停止和纹理停止。

回滚分两层：虎牙 URL/令牌修改可独立回滚；Windows 纹理包装可独立回滚。上游 merge 前完整回滚点为 `d3c810a16df644564f596f29b1240e71a8940981`。
