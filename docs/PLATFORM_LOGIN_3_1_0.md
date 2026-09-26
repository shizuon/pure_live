# 3.1.0：实际画质与账号登录

开发基线 `9bba221a`。沿用 [平台画质审计](PLATFORM_QUALITY_AUDIT_2026_09_26.md)
的逐平台复现和来源判断；本批独立工作区，不修改3.0.24构建提交。
用户授权全部已确认问题修复、统一易用登录、检查后合并master，版本改为3.1.0。
未授权无审查合并上游；本批不合并上游。

处理范围：YY回退实际画质、B站菜单外确认、抖音账号/匿名会话隔离、
HLS缺失分辨率与编码分组、快手逐档选择编码、Kick单流不冒充原画。
保留媒体库、HDR、硬解、双流时钟和录制互斥，不声称突破平台账号权益。

登录采用现有WebView的官方页面，替换虎牙、抖音、快手、Twitch、YY、SOOP
旧的手填主入口，统一斗鱼入口；B站保留官方二维码并修补生命周期与跨站退出。
仅从当前应用WebView读取目标站点会话，不读取外部浏览器或密码。
高级手填保留；旧路由兼容；会话缺失/未确认不能显示已验证登录。
无现有认证播放协议的Kick/YouTube/CC/IPTV不添加虚假的登录按钮。

每项需确定性回归、一次最终静态检查、完整测试。所有应用仅GitHub构建；
真实扫码、短信、验证码及各站账号实际权益仍需用户实机验证。
最终证据、合并与构建状态在本文件补齐，不把代码测试等同于实机通过。

## 本批实现

| 根因 | 实施 | 回归重点 |
| --- | --- | --- |
| YY回退仍确认原画 | 移动HLS宽高生成真实描述，独立确认id，沿统一解析传递到A/B/录制 | 360P回退不保留原画，缺宽高明确未确认 |
| B站确认档不在旧菜单 | 解析时提供确认档的可播放菜单项 | qn=250不会回退到请求10000标签 |
| 抖音静态Cookie遮蔽账号 | 静态缓存只保留游客字段，账号读取设置优先；异步返回后再核对新登录 | 登录、退出、匿名请求期间完成登录 |
| Twitch认证头缺失 | 当前会话auth-token用于GraphQL OAuth头；退出清除 | 不把OAuth发往媒体CDN |
| 快手整组H.264优先 | 每档优先AVC，保留HEVC独有档，合并同编码CDN | HEVC原画不会因有AVC低档而消失 |
| HLS按码率猜分辨率 | 缺分辨率显示Mbps/未确认；精确FPS、CODECS、AUDIO、字幕组进入身份 | 不猜1080P，不把异编码/音轨当线路 |
| Kick单流冒称原画 | 单一媒体清单显示未确认 | 不伪称最高档 |
| 多站手填账号入口 | 共用官方WebView登录页、站点会话提取、切换/退出、折叠高级输入 | 域名边界、关闭/重入、晚到响应、掩码输入 |
| B站退出清空所有站点 | 本地会话清理与站点网页清理分离；仅B站域 | 其他站Cookie保持；旧资料响应不能恢复登录 |
| B站二维码竞态 | 换二维码代次隔离、单次轮询、成功/失败/退出停止定时器 | 关闭生成、重叠轮询、迟到成功不得保存 |
| Mac产物校验瞬时繁忙 | hdiutil只对资源繁忙重试3次；其他错误立即失败 | 校验损坏不重试为成功，次数有界 |

登录支持范围：Mac/Windows/Android/iOS使用已有原生WebView；
Linux目前插件缺少WebView实现，只能使用B站官方扫码和其他平台高级入口，
不宣称已经实现Linux全站无Cookie登录。Android TV共用arm64 APK；
这是共用布局构建，不等于遥控器/TV扫码已实测。32位Android和独立TV仓库
不属于当前arm64工作流产物，不能冒充已构建。

SOOP/CC等仅有证据缺口的平台不随意改取流参数；已有公开流能力保留。
不新增Kick/YouTube认证取流，不将登录UI作为解锁地区/会员内容的承诺。

旧账号配置继续可读。新设置导出不含任何平台会话；本机Hive持久化保留；
导入缺少Cookie字段的配置不会清空当前会话。备份迁移不再悄悄覆盖登录。
旧Cookie路径继续路由到新账号页（历史 `/douyu_cookie` 仍对应抖音）。

## 验证与全平台交付

- 首轮受影响模块44项测试通过。完整回归首轮580通过/1失败，失败是旧心跳
  测试在并发编译负载下超过40ms真实截止时间；改用注入时钟，保持生产默认
  DateTime.now，覆盖心跳保持连接及真正超时后触发恢复。最终局部13项通过。
- 完整静态分析0 error / 0 warning；4条info中的2条新增缺括号提示已补齐，
  另2条为Kick/Twitch既有null-aware风格提示。Python包验证8项通过，
  包括新DMG临时繁忙/真实损坏/有限重试三种路径。
- 修正时间夹具后的最终完整Flutter回归 **581/581通过**（56秒运行阶段），
  `local-artifacts/full-tests-3.1.0-final.log`。不是仅复跑失败项后宣布全套通过。
- 版本统一 `3.1.0+4113`；后续从3.1.0递增，build不重置，避免平台升级倒退。
- 当前用户仓库Secrets列表为空，Android没有正式签名密钥，Windows无MSIX证书。
  Android用明确标注的临时测试证书提供Actions测试APK，不发布为正式升级包；
  Windows仍提供EXE安装器和便携ZIP；iOS提供普通未签名IPA供自行签名。
- 构建按Mac→Android→Windows→Linux→iOS串行，每阶段下载核验后下一阶段。
  Mac DMG/ZIP、Windows安装器与便携包、Linux归档、iOS IPA和各SHA作为3.1.0
  Release候选资产；Android签名限制单列。用户已授权成功后直接发布。
- 3.0.24 run `36236597046` 编译成功但校验资源临时繁忙；新任务取代旧版发布，
  不再发布3.0.24，也不把旧平台产物挂到3.1.0。

## 最终源码与构建队列

- `28e06159a5fa98dcf558868b046f94ee09887804` 已快进合并并推送用户仓库
  `master` 与 `feat/platform-quality-login-20260926`。没有上游merge。
- [首轮云构建 36240491330](https://github.com/shizuon/pure_live/actions/runs/36240491330)
  从该源码启动，先完整质量，再仅Mac。所有后续平台按同业务源码串行。
- 全平台尚未交付；顺序为Mac核验→Android测试APK核验→Windows核验→Linux核验
  →普通未签名iOS IPA核验→统一Release发布及索引。每阶段成功不结束整体任务。
- 本地Git曾因同步产生非法引用 `refs/remotes/fork/feat/global-platforms-20260921 2`，
  已备份至忽略目录 `local-artifacts/git-ref-backup/` 后移出refs命名空间；
  正常引用、历史与用户文件未删除。另出现未跟踪 `assets/version 2.json`，保留不提交。

最终完整回归和源码合并已完成；各平台产物SHA及Release地址尚待补齐。

## 云端已完成阶段

**发布前新增修复正在验证**：用户继续反馈B站重连、Kick分区及大偏移停顿，
见 [增量记录](BILIBILI_KICK_FOLLOWUP_2026_09_26.md)。下述Mac/Android仅属于
旧业务提交，不含新增修复，最终Release不得直接复用；增量合并后重新串行构建。

增量最终代码验证现已完成：完整Flutter **606/606通过**，lib/test分析0error/
0warning。增量包含B站单一恢复流程及ACK、Kick按需分页、大偏移预读与低缓存
停止加速、Mac手动A/B诊断。保持 `3.1.0+4113` 未发布批次版本，最终资产全部重建。

最终增量已于提交 `df46251fff7607a7598f521a5b96093ff11238cc` 快进合并并推送
master/开发分支。[最终Mac云构建 36248835900](https://github.com/shizuon/pure_live/actions/runs/36248835900)
已启动完整质量检查和Mac编译，后续各平台从这一业务版本串行交付。
下面旧Mac/Android产物仅作历史证据，不属于最终Release。

- Mac运行 `36240491330` 成功，云端完整Flutter **581项通过**，包验证通过。
  下载后再确认 `3.1.0 (4113)`、主程序 `x86_64 arm64`、ZIP CRC、两包SHA256、
  `bash tool/verify_dmg.sh` 均成功；没有安装、挂载或启动应用。
- [Mac候选附件](https://github.com/shizuon/pure_live/actions/runs/36240491330/artifacts/10906552005)
  有效期至 `2026-09-29 12:37:53 UTC`。最终仍将上传到统一Release作为稳定下载入口。
- `PureLive-3.1.0-4113-macos-universal.dmg`：122279188字节，
  SHA256 `0d036bcd55023dba953927225eb27356524787cb316dfe2af4a339e7d659efba`。
- `PureLive-3.1.0-4113-macos-universal.zip`：106646422字节，
  SHA256 `b5b5f8208584430dd549e9944b217622b1d92de3164822abb88a909db940124c`。
- 本机忽略目录 `local-artifacts/cloud-macos-3.1.0/` 保存产物与验证JSON；
  `local-artifacts/cloud-macos-3.1.0.log` 保存云端完整日志。
- [Android运行 36243216645](https://github.com/shizuon/pure_live/actions/runs/36243216645)
  已在Mac核验后启动，仅Android测试签名。所用分支较Mac业务SHA仅有交付文档变更。
  Android完成核验后继续Windows、Linux、iOS；尚未发布Release。

## 最终业务版本交付（df46251f）

- 最终Mac运行 `36248835900` 成功，云端 **606项测试通过**。下载后再次确认
  `3.1.0 (4113)`、`x86_64 arm64`、ZIP CRC、SHA256、DMG verify全部通过，
  不挂载、不安装、不启动应用。
- [最终Mac附件](https://github.com/shizuon/pure_live/actions/runs/36248835900/artifacts/10908975991)
  截止 `2026-09-29 15:01:00 UTC`；正式交付仍等待统一Release。
  本机目录 `local-artifacts/cloud-final-macos-3.1.0/`，云日志
  `local-artifacts/cloud-final-macos-3.1.0.log`。
- DMG：122010111字节，
  SHA256 `c0cf469d3343935a0a146113ecc5480ab513642d11a9744e54513c8570f458ed`。
- ZIP：106676845字节，
  SHA256 `4776b7262fb8ecac4a99b96709ec350248d869051011567cdd48d3ec4b0953af`。
- [最终Android运行 36251790710](https://github.com/shizuon/pure_live/actions/runs/36251790710)
  已在最终Mac下载核验后启动，仅Android测试签名；ref后续仅有文档差异。
  后续Windows、Linux、iOS仍待串行构建和核验；全平台Release尚未发布。

- 最终Android运行 `36251790710` 成功，源码 `24fc81c6415c4f3aee77eb0560e6aed10589bc09`
  与最终Mac业务源码仅文档不同。云端包内容验证（1261个Flutter资源）、v2签名、
  manifest `3.1.0 / versionCode=6113 / Flutter build=4113` 通过。
  下载后SHA、ZIP CRC、唯一 `arm64-v8a`、版本资源及Flutter/App原生库通过。
- [最终Android测试附件](https://github.com/shizuon/pure_live/actions/runs/36251790710/artifacts/10909151670)
  截止 `2026-09-29 15:27:25 UTC`；临时测试签名，不是正式升级包。
  `PureLive-3.1.0-4113-android-arm64-v8a-test-signed.apk`：118799847字节，
  SHA256 `645501b046ba46365ddeb0aaba1236651b470dd2e1700ca23e31ec1fd7a1f092`；
  证书SHA256 `3e3e3bac96e3342e119f5734607d1da859eeaa49660d677e8994c8d7ccd11d76`。
  本机产物及验证JSON位于 `local-artifacts/cloud-final-android-3.1.0/`，
  云日志为 `local-artifacts/cloud-final-android-3.1.0.log`；未安装或操作设备。
- [最终Windows运行 36252815489](https://github.com/shizuon/pure_live/actions/runs/36252815489)
  已在Android下载核验后启动，仅Windows开启；须安装器/便携包及云端重新下载验证
  全部成功后再继续Linux、iOS。全平台Release仍未发布。
