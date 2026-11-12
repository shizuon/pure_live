# 抖音分区、画质与 Mac 本地交付

本轮基线为 `94e0f9f6668c2b4bca0d7b8e9b6315a7deae54ba`，版本为
`3.1.3+4116`。交付范围为 macOS 本地构建与安装。

## 分区

2026-11-12 对照官网页面与实际接口，目录为聊天、音乐、游戏、二次元、舞蹈、
文化、生活、运动八个大类。游戏菜单包含九个推荐子类，“更多”展开同一组条目。
应用沿用官方 `categoryData` 的顺序与分区标识，并通过现有分类标签页保留层级。
每组“全部”入口使用父分区标识。
分类分页更新替换普通列表的当前切片，反复切换保持子项数量与顺序。

分类房间接口的 `count` 和 `offset` 使用调用方页大小。
官方接口对 `count=12` 返回 12 个房间及下一偏移 12；旧实现固定请求 15 项，
会与桌面分页期望的页大小发生偏差。

## 取流

每档画质保留官方 `main` 与 `backup` 的 FLV、HLS 地址，过滤 `ao`、`audio`
纯音频候选。新旧画质别名归入同一选项，线路顺序保持主线路优先。

房间 API 回退到网页时，HEAD 和页面 GET 继续携带当前账号会话；页面返回的
访客标识与 nonce 仅补齐缺失值。退出登录后继续使用现有匿名会话管理。

冻结上游 `liuchuancong/pure_live` 提交
`ec69735209e041c29ef281d7a3a87660ab3b95e4`，路径为
`lib/shared/platforms/douyin/douyin_site.dart`。遗漏备用线路与网页回退丢失账号
会话均在该提交存在，来源分类为 `upstream-existing`。
上游 `lib/domains/live/presentation/areas/area_display_config.dart` 也将抖音列入
`flatAreaSites` 并展开各组子项，分类混排同属 `upstream-existing`。

本轮未修改设置结构、账号保存方式、播放器解码配置或双直播同步算法。
回退代码可还原本次抖音修复提交；安装保留旧应用包与现有应用数据。

## 已完成验证

- 47 项相关回归通过，覆盖分类目录、分页与切换、匿名及登录会话、网页回退、
  主备线路、画质别名、弹幕协议、观看人数、搜索及播放器选流。
- 8 个改动 Dart 文件定向静态分析通过，格式化与 `git diff --check` 通过。
- 应用最终解析器对匿名及账号实际响应均返回 17 个房间与画质组合、56 条线路，
  覆盖 3 个直播间；没有额外未采样的旧格式线路。
- 账号会话接口返回有效会话。账号模式 56 条线路均读取有效媒体；匿名模式
  55 条首次通过，1 条备用 HLS 刷新房间地址后读取有效 TS 分片。
- HLS 采样跟随多层播放列表直到媒体分片；CDN 请求不携带账号 Cookie。

测试记录位于 `local-artifacts/build-records/douyin-focused.json`、
`douyin-fixes-focused.json` 与 `douyin-analysis.json`。
性能优化沿用 `playback-focused.json` 的 56 项回归与 `playback-analysis.json`。
