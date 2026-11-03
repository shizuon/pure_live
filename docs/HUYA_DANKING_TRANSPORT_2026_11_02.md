# 虎牙 DANK1NG 线路 1/2：WUP HTTPS 与页面模板签名

## 范围、冻结点与来源

- 用户现象：DANK1NG 的虎牙线路 1、2 收到一段流后停住并出现 exception；用户未提供异常原文、播放器或客户端平台。不能把本次 HTTP/媒体证据等同于已采集该客户端异常。
- 官方房间：[DANK1NG / 10188](https://www.huya.com/dank1ng)，由虎牙页面及[官方资讯](https://blog.huya.com/news/48595)核实；本次公开响应为 `profileRoom=10188`、`state=ON`、`isReplay=false`。
- 维护分支基线：`70909fb54ff16fdfa50b4cc30f440efcaeb9f683`；业务源码与调查开始时的 `0c1d5ed741e2790946019da494d96794e7cbdfd6` 相同。
- 上游冻结：`1961157a6217216486288dfbdbf0d7b932c13bd1`。其虎牙代码已经移动到 [`lib/shared/platforms/huya/huya_site.dart`](https://github.com/liuchuancong/pure_live/blob/1961157a6217216486288dfbdbf0d7b932c13bd1/lib/shared/platforms/huya/huya_site.dart)，使用 HTTPS 和模板签名，并限制原生 `sFlvToken` 只用于 FLV。
- 主来源：`fork-regression`。`c66c39c398e0e4162f9b0c40ddc2aa72730f6686` 为兼容历史页面 token，引入“WUP 失败时页面签名原样后备”；它把含 `fm` 的模板也透传了。当前 HTTP WUP 被拒绝使这条缺陷路径稳定可达；该触发条件属于本次观测的外部接口行为，不能推断平台何时或在哪些网络全面改变了策略。
- 上游[原生令牌长读记录](https://github.com/liuchuancong/pure_live/blob/1961157a6217216486288dfbdbf0d7b932c13bd1/docs/HUYA_NATIVE_LEASE_FIX_2026_09_05.md)提供了相同方向的交叉证据。本次只适配取流契约，不合并其架构、播放器定时器或租约管理。

当前页面顺序为 AL FLV、AL HLS、TX FLV、TX HLS、HS FLV、HS HLS，分别对应线路 1～6。线路编号来自本次响应，不假设每个房间始终返回相同顺序。以下时刻均为 2026-11-02 UTC（本地新加坡时间加 8 小时）。

## 第一个错误状态与分层复现

1. `HuyaSite.getPlayUrl()` 首先调用 `getCndTokenInfoEx()`。旧地址 `http://wup.huya.com` 返回 HTTP 403，进入页面 token 后备。
2. 页面材料包含 `wsSecret/wsTime/fm/ctype/fs`；`fm` 是还要结合流名、身份、序号与时刻签名的模板。旧后备分支跳过 `buildAntiCode()`，直接把捕获的短效签名交给播放器。
3. FLV 能返回 HTTP 200 和缓存开头，但随后 EOF；HLS 能暂时返回清单，但捕获的 `wsTime` 到期后 AL 返回 HTTP 403。这是媒体输入端失败，不能用窗口纹理故障解释。
4. 取流失败随后才进入播放器错误/EOF 与重连路径。重试若继续拿到 HTTP WUP 403 和未签名后备，就可能重新制造同类坏地址；增加播放器重试次数不能修复这个输入契约。

### WUP 请求层

匿名 TARS 请求与当前原生契约一致：`getCdnTokenInfoEx`、`liveui`、当前流名、`sFlvUrl=''`、`iLoopTime=0`、`iAppId=66`，`tId.sHuYaUA=pc_exe&7060000&official`，没有账号 Cookie 或用户凭据。

| 地址 | 结果 | 响应含义 |
| --- | --- | --- |
| HTTP WUP | 多次 403，`Server=HUYA/2.15.3` | 旧代码无法取得新原生令牌 |
| HTTPS WUP | 复核两次 200，响应 206 字节 | `sFlvToken` 非空、`ctype=huya_pc_exe`、`iExpireTime=300` |

首个 HTTPS 探测也出现过 403，随后复核请求正常。因此 HTTPS 修复仍需要可靠的失败后备；不能以协议升级代替模板签名或将外部接口描述为始终可用。

### FLV 传输层

同一 DANK1NG 房间、公开 `ratio=500`、AL CDN、HYSDK 请求头，跟随同类 CDN 302 路由。读取有时间和字节上限；长读只统计字节和事件，首包格式检查的少量头字节及清单仅在临时目录留存，不提交媒体或签名材料。

| 凭据策略 | HTTP | 持续时间 | 字节 | 结束原因 |
| --- | --- | --- | --- | --- |
| 页面材料原样，当前失败后备语义 | 200 | 0.302 秒 | 490,740 | EOF |
| WUP 材料原样，不做最终签名 | 200 | 0.274 秒 | 524,591 | EOF |
| 页面 `fm` 经现有 signer | 200 | 35.063 秒 | 3,060,320 | 主动达到时间上限 |
| HTTPS WUP `fm` 经现有 signer | 200 | 35.072 秒 | 3,060,320 | 主动达到时间上限 |
| HTTPS WUP 原生签名长读 | 200 | 180.092 秒 | 12,825,239 | 主动达到时间上限 |

同签名策略的 TX FLV 对照也在约 0.338 秒、492,533 字节后 EOF，因此这里证明的是旧后备取流契约错误，并非“只有 AL 会断”。页面原样地址在另一轮重开也出现过 403，不能把 HTTP 200 首包作为稳定播放门禁。

### HLS 请求层

原页面签名的 `wsTime` 对应 12:09:27。AL 原地址在 12:06:33 至 12:09:21 仍返回 200，媒体序列由 5632 推进到 5713；12:09:37 开始返回 403，后续检查继续失败。TX 顶层清单有时仍为 200，但子清单请求也出现 403；HS 在同一过期样本下仍能返回清单和 TS 字节。

签名后的样本可继续取得 AL/TX/HS 的清单与 TS 字节。曾用 WUP 材料作 HLS 诊断对照，但该短时 200 不构成跨协议授权契约：响应类型只声明 `sFlvToken`，因此最终修复及生产路径验证均使用独立 `hlsAntiCode`。

## 最小修复与相邻模式

- 所有虎牙 WUP 调用共用 `HuyaRequestParams.wupUrl=https://wup.huya.com`，包括两个已有消息板入口。通用 TARS 网络层不变。
- FLV 继续优先原生 WUP；HLS 不再请求或借用 FLV 令牌。缺少 HLS 材料时明确失败，不用其他协议的 token 伪造成功。
- 来自 WUP 或对应协议页面的材料都经过既有 `buildAntiCode()`。其 `fm` 缺失边界保留 opaque token 原样；含 `fm` 时产生最终签名。清晰度 `ratio`、codec 和 CDN HTTPS 归一化保持原契约。
- 复用现有 signer 的近到期模板续签逻辑；本次没有引入新的签名算法、定时器或额外重试。确定性测试覆盖已经过期的 HLS 页面模板，防止再次透传捕获签名。
- 保留同 stream 的 FLV 请求合并、两分钟成功缓存、三秒整体超时和三十秒失败冷却；HTTP 失败不再意味着输出未签名模板。
- 普通播放、全屏、小窗、音频与录制共用修正后的取流入口；播放和录制共用 `PlaybackHeaderResolver`，补充冷启动请求头一致性回归。

冷启动浏览器 UA 的原生 FLV 对照在 35.039 秒、2,946,431 字节内也正常。没有证据把它判为本次错误根因，因此不修改默认 UA，也不把 HYSDK 探针结果冒充生产冷启动验证。

## 验证与验收边界

首轮新增/调整的离线回归在未修复业务源码上得到 11 通过、4 失败，失败点分别为 HTTP 地址、页面模板缺少最终签名、HLS 借用 FLV token、HLS 错误请求 FLV 接口。随后补充过期 HLS 模板和播放/录制请求头边界。最终 **21 条离线回归 + 1 条真实 Dart 外网探针全部通过（22/22）**。

实际生产函数探针使用 `HuyaSite.getPlayUrl()` 完成真实 HTTPS WUP 编解码及签名，`PlaybackHeaderResolver` 生成媒体请求头，`FFmpegHeaderFactory` 验证录制头相同。它将 `playUserAgent` 置空，明确测试原来的浏览器冷启动 UA；没有先用 HYSDK 替换生产头。AL HLS 使用自己的页面材料，FLV 断言使用原生 `ctype=huya_pc_exe`。

| 实际 Dart 路径 | 时间/采样 | 结果 |
| --- | --- | --- |
| AL FLV，冷启动生产头 | 180.005 秒，12,903,357 字节 | HTTP 200；主动时间上限结束，无 EOF；最大数据到达间隔 963 ms |
| AL HLS，同一签名地址，冷启动生产头 | 12:18:14～12:21:16，7 次清单与分片采样 | 全部 200，媒体序列 5964→6052；签名地址在采样过程中未替换 |

最大数据到达间隔是网络指标，不是解码帧时间。该证据支持本次不修改默认 UA。

验证通过共享 `/tmp/pure-live-heavy-build.lock` 守卫，使用已有 Flutter 3.47.0、`--no-pub --concurrency=12`，保留缓存。命令为：

```text
python3 local-artifacts/run_guard.py huya-focused-and-production \
  ../flutter-overlay-sdk/bin/flutter test --no-pub --concurrency=12 \
  test/huya_play_url_test.dart test/playback_header_resolver_test.dart \
  local-artifacts/huya_production_transport_test.dart
```

本地记录：`local-artifacts/build-records/huya-focused-and-production.json` 和同名日志；总耗时 230.84 秒、退出码 0、峰值 RSS 1,398,145,024 字节。记录中的 SHA 是修改前基线，`dirty=true` 表示实际测试包含本次最终业务补丁；后续仅补充本文结果。外网探针和临时公开响应不加入默认离线测试，不提交原始签名材料。静态分析和完整回归由父任务在最终整合提交统一执行，本子任务未重复运行。

本次不启动应用、不连接设备、不安装软件、不触发应用构建或发布。未采集 Windows/macOS/Android/iOS 解码画面、原始播放器 exception 或高码率 30M 播放；公开的低码率媒体读取不能替代这些证据。源码与取流结论应由父任务整合后进入正式质量门和既定平台交付，不宣称真实客户端已验收。

回滚本次定向提交即可恢复原取流策略；无设置或数据迁移。回滚会同时恢复已经复现的 HTTP WUP 和未签名模板后备缺陷。


## 整合后的最终质量门

父任务已在干净提交 `a8c4ae98683e7c343c87d4a7fbdf6213d5d71a1d`
完成静态分析（0 error、0 warning，2 条既有风格 info）及完整 **657/657**
Flutter 回归。该版本同时包含本轮桌面小窗和斗鱼续期功能；后续安装包与发布
状态以 [桌面交付记录](DESKTOP_PIP_DOUYU_REFRESH_2026_11_02.md) 为准。
