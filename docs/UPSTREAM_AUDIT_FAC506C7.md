# 上游同步审计：fac506c7

- fork_sha: `d3c810a16df644564f596f29b1240e71a8940981`
- upstream_sha: `fac506c76085a547af06ba8541473a836e108c16`
- merge_base: `53bf0411eb09728773427bbf71ab59198e0a413b`
- incoming_range: `53bf0411eb09728773427bbf71ab59198e0a413b..fac506c76085a547af06ba8541473a836e108c16`
- review_date: `2026-08-29`
- report: manual macOS review; the repository PowerShell report runner is unavailable on this host

## file_review

| 状态 | 文件 | 风险 | 上游目的 | 维护分支相关实现 | 处置 |
| --- | --- | --- | --- | --- | --- |
| A | `docs/BUGFIX_SCROLL_BOUNDARIES_3_0_21.md` | low | 记录分类导航越界修复 | 无冲突 | accept |
| M | `lib/common/widgets/pure_live_scroll_physics.dart` | medium | 增加有界分类滚动策略 | 桌面播放控制仍使用原交互 | accept |
| M | `lib/core/danmaku/huya_danmaku.dart` | high | 更新 Cookie、握手、重连日志与协议解析 | 必须保留 15 秒 WebSocket 重连和代次隔离 | adapt |
| M | `lib/core/site/huya/huya_site.dart` | high | 重写房间解析、令牌缓存与 URL 解析 | 必须保留 HTTPS、FLV/HLS 令牌和参数去重 | adapt |
| M | `lib/modules/areas/areas_controller.dart` | medium | 分类索引钳制 | 无冲突 | accept |
| M | `lib/modules/areas/areas_grid_view.dart` | medium | 控制器驱动有界导航 | 无冲突 | accept |
| M | `lib/modules/areas/areas_list_controller.dart` | medium | 新增可见分类索引控制 | 无冲突 | accept |
| M | `lib/modules/areas/areas_page.dart` | low | 注入列表控制器 | 无冲突 | accept |
| M | `lib/modules/areas/favorite_areas_controller.dart` | medium | 收藏分类索引钳制 | 无冲突 | accept |
| M | `lib/modules/areas/favorite_areas_page.dart` | low | 收藏分类接入有界滚动 | 无冲突 | accept |
| M | `lib/modules/favorite/favorite_controller.dart` | low | 恢复时刷新条件调整 | 与首页刷新配置共同验证 | accept |
| M | `lib/modules/favorite/favorite_page.dart` | medium | 有界平台导航 | 无冲突 | accept |
| M | `lib/modules/home/home_page.dart` | medium | 恢复时应用 RefreshConfigController | 保留现有首页控制器生命周期 | accept |
| M | `lib/modules/live_play/controllers/live_play_controller.dart` | high | 清理与分类滚动物理接入 | 双流退出、B 弹幕源和 15 秒重连不能被覆盖 | adapt |
| M | `lib/modules/live_play/dialogs/play_other.dart` | low | 弹窗滚动改为有界策略 | 无冲突 | accept |
| M | `lib/modules/live_play/widgets/danmaku/danmaku_tab.dart` | medium | 弹幕列表改为有界策略 | 保留 A/B 弹幕源选择和延迟 | adapt |
| M | `lib/modules/live_play/widgets/layout/live_play_video.dart` | high | 调整 LivePlayVideoFrame 布局 | 保留双流校准画面和 HDR 窗口修复 | adapt |
| M | `lib/modules/live_play/widgets/video_player/video_controller_panel.dart` | medium | 控制面板滚动改为有界策略 | 保留解说入口与录制禁用 | adapt |
| M | `lib/modules/popular/popular_controller.dart` | medium | 热门平台索引钳制 | 无冲突 | accept |
| M | `lib/modules/popular/popular_page.dart` | medium | 热门页有界导航 | 无冲突 | accept |
| M | `lib/modules/search/search_page.dart` | low | 搜索滚动策略统一 | 无冲突 | accept |
| M | `lib/modules/search/search_platform_strip.dart` | low | 平台条有界滚动 | 无冲突 | accept |
| M | `lib/modules/web_dav/web_dav_page.dart` | low | WebDAV 页面滚动策略统一 | 无冲突 | accept |
| M | `lib/recorder/widgets/recorder_bounded_scroll.dart` | medium | 复用公共滚动物理实现 | 双流录制禁用不受影响 | accept |
| A | `test/area_category_switch_test.dart` | low | 锁定分类切换边界 | 无冲突 | accept |
| A | `test/bounded_navigation_scroll_test.dart` | low | 锁定有界滚动策略 | 无冲突 | accept |
| M | `test/search_scroll_policy_test.dart` | low | 适配公共滚动物理实现 | 无冲突 | accept |

## semantic_change_ledger

| commit | file / module | upstream intent / before → after | implementation | issue_and_bug_mapping | quality_assessment | fork_feature_impact | disposition | regression_plan |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `c5944dd5a529cd93eb29486500abd5d496618f80` | Huya site/danmaku | 页面令牌优先 → WUP 新令牌和短时缓存；弹幕握手与解析扩展 | 增加请求合并、2 分钟缓存、解析容错和日志 | #815/#816；可能修正 AL CDN 使用旧令牌，但提交标题无法反映 1000+ 行风险 | 房间解析改进可接受；直接使用 HTTP、无条件追加 codec、忽略 HLS/FLV 各自令牌会回退既有修复 | 影响所有虎牙线路和 B 解说源 | adapt | URL 构造、缓存、线路、HTTPS、弹幕重连测试；脱敏接口探测 |
| `c5944dd5a529cd93eb29486500abd5d496618f80` | `live_play_controller.dart` | 删除无效清理行 | 局部删除 | 无独立 Bug | 与双流生命周期合并检查 | 可能与退出双流清理相邻 | adapt | 双流进入/退出测试 |
| `1d8eb5a45573f4ef92d6563922fae591d73f7243` | Huya import / live video layout | 移除未使用导入并简化布局 | 格式与 Expanded 调整 | 无独立 Bug | 低风险，但布局是双流/HDR 高风险面 | 可能影响窗口和校准画面 | adapt | macOS 普通窗口、全屏、校准画面 Widget/构建检查 |
| `0ec5f1cb5123f96516f27eae1a27f2a1c67c622d` | categories/favorite/popular/search/scroll | 未钳制导航 → 统一有界索引与滚动物理 | 公共 physics、控制器钳制与确定性测试 | 分类快速切换越界 | 实现集中且测试充分 | 不改变播放器状态，只触及相邻 UI 滚动 | accept | 新增 3 组滚动/分类测试和完整 Widget 回归 |
| `fac506c76085a547af06ba8541473a836e108c16` | home/favorite refresh | 恢复时无配置控制 → 由 RefreshConfigController 决定刷新 | 首页恢复回调增加配置判断 | 无独立 Bug | 复用已有控制器，需确认注册顺序 | 不影响播放会话 | accept | 首页控制器与 Analyze |

## issue_and_bug_mapping

| Issue / Bug | 版本与日期 | 维护分支状态 | 来源分类 | 首次错误状态 / 根因 | 代码落点 | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| [#815](https://github.com/liuchuancong/pure_live/issues/815) | 3.0.7, Windows x64, 2026-08-29 | present | upstream-existing | 虎牙 AL CDN（显示线路 1/2）连接失败或数分钟后停止；视频停止但弹幕会话继续。2.9.8→3.0.7 同时删除 Windows 纹理视口约束并多次改写 live demuxer 属性，最新上游仍保留这些差异。真实根因须分开验证网络输入是否继续与纹理是否继续呈现。 | Huya URL/令牌；MediaKit live properties；Windows video texture | 采用 WUP 新令牌但保留安全 URL；恢复非 seekable live 属性和有界 Windows 输出，禁止用自动换线掩盖 |
| [#816](https://github.com/liuchuancong/pure_live/issues/816) | 3.0.7, Windows x64, 2026-08-29 | present | upstream-existing | 与 #815 同根因；用户证据显示线路 4 正常，支持 CDN/令牌差异而非弹幕或房间生命周期 | 同上 | 与 #815 合并修复和验证 |
| macOS HDR 窗口闪烁 | 双流迁移功能 | already-fixed | fork-regression | Impeller 宽色域窗口合成 MediaKit 双纹理时闪烁 | `macos/Runner/Info.plist` | 保留 `FLTEnableImpeller=false`，上游布局调整不得覆盖 |

## fork_feature_impact

- 普通、横屏、全屏、画中画、小窗、音频模式：保留上游布局意图；双流 B 校准画面和 HDR 开关不变。
- 播放器、清晰度、线路和弹幕会话：采用虎牙新令牌请求合并；保留显式线路选择，不做自动换线；A/B 弹幕源和 15 秒重连不变。
- 设置默认值、迁移、备份恢复：本批次没有新持久化键。
- 首页、关注、搜索、排行和平台接口：接受有界滚动和恢复刷新配置。
- Windows 窗口、安装、数据目录和资源趋势：恢复有界、去抖的纹理输出尺寸；Windows 实机仍需用户验证。
- 版本、签名、更新源、工作流和 Release 资产：本批次没有入站改动，保持维护分支现状。

## quality_assessment

- 正确性与边界：滚动变更有确定性测试；虎牙提交标题与实际范围严重不符，URL 构造存在已知回退，不能原样接受。
- 异步竞态和生命周期：令牌请求需要合并并设置失效时间；弹幕必须保留 generation 检查与手动关闭语义。
- 资源释放：公共滚动物理不持有资源；WebSocket Timer/订阅继续由 stop/close 释放；Windows resize Timer 必须在 dispose 取消。
- 性能与网络请求：WUP 令牌按 stream 合并并短时缓存，避免线路列表并发重复请求；不新增播放期轮询或自动换线。
- 数据迁移：无。
- 更优方案与决定：对虎牙采用“新鲜 WUP 令牌优先、协议页面令牌后备、HTTPS 与参数归一化”；对 MediaKit 用可测试的 live property policy，不把文件流属性混入直播流。

## conflict_resolution

- 预期文本冲突：`live_play_controller.dart`、`live_play_video.dart`、控制面板和虎牙文件。
- 无文本冲突但存在的语义冲突：上游虎牙 URL 构造撤销 HTTPS/协议令牌/参数去重；上游布局可能遮蔽双流入口。
- 最终候选结果：接受分类滚动、首页刷新、虎牙解析和令牌缓存；重写虎牙 URL 策略并保留全部双流功能。
- 版本、更新源、签名和发布资产：没有上游变化，不调整。

## regression_plan

- 单元 / Widget：虎牙 URL 与令牌回退、native live properties、Windows 输出尺寸、15 秒弹幕重连、双流同步/弹幕源、上游滚动测试。
- Android：本轮不进行设备操作；公共播放器属性只通过确定性测试和完整回归验证。
- Windows：需要 Windows x64 实机验证线路 1–6 连播 30 分钟；当前 Mac 只提供源码和自动化证据。
- 接口与网络故障：脱敏记录 CDN/协议/状态码，不输出 Cookie、wsSecret 或完整 URL。
- 旧配置、迁移和回滚：无数据迁移；回滚点为合并前 `d3c810a1`。
- 未覆盖：Windows MediaKit 实际纹理、硬解和长播网络行为不能从 macOS 外推。

## verification_plan

- 静态审计：`tool/audit_repository.py`（合并后）。
- `git diff --check`：必须通过。
- Focused / Full：先运行虎牙、播放器、双流、弹幕和滚动定向测试，再运行完整测试。
- Analyze：Flutter 3.47.0，修改完成后一次。
- 目标平台构建：macOS Release 供用户测试；Windows 输出调试文档和源码，不伪称实机构建。
- 设备采样：用户执行 Windows 线路 1–6、窗口/全屏和 30 分钟长播；Mac 执行构建与可启动性检查。
- 外部接口探测：2026-08-29 已脱敏确认在线房间返回 AL/TX/HS，页面基址为 HTTP 且 FLV/HLS 均带令牌。

## 合并结论

- 最终 merge 提交：合并完成后回填。
- 接受：滚动边界、首页刷新、虎牙解析容错和令牌请求合并。
- 适配/重写：虎牙 URL、双流相邻 UI、弹幕生命周期、MediaKit live 属性与 Windows 输出尺寸。
- 已知限制：未在 Windows x64 实机复现；因此自动化修复完成后仍标为“待用户长播验证”，不提前关闭 #815/#816。
- 回滚点：`d3c810a16df644564f596f29b1240e71a8940981`。
