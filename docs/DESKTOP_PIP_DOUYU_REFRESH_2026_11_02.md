# Windows / macOS 小窗与斗鱼启动续期

开发基线：用户仓库 `shizuon/pure_live` master
`ddd283c8a754c20e935c6dfbc21b81e4885a3863`。原项目当前参考提交
`1961157a6217216486288dfbdbf0d7b932c13bd1`；本批没有合并上游。
原工作区存在同步/读取停顿，使用同一用户仓库的独立干净检出。

## 编辑前的来源与根因

- Mac 小窗属于本次明确要求的功能扩展。基线播放器按钮、窗口服务、
  enter/exit 分支均只开放 Windows/Android。现有 CompactDanmakuOverlay
  已在小窗叠加视频上，复用同一播放器与房间弹幕连接即可支持 Mac。
- Windows 小窗恢复属于 `fork-regression`：WindowHelper 进入时不防重入，
  可把已缩小的矩形保存成正常窗口；退出硬编码关闭置顶和最小 800×600，
  与桌面初始化最小 400×300 不一致，也不恢复最大化状态。
- 斗鱼启动续期缺失属于 `fork-regression`：账号功能仅在 Web 登录页读取
  主站 acf_* 并保存。启动没有续期；请求头还每个进程生成 DID，覆盖登录
  Cookie 的设备号。短期凭据过期后继续发送同一旧值。
- 自动续期需使用用户已登录 WebView 的 passport 长期票据，不可将游客
  Cookie 或页面加载成功冒充账号续期。采用局部适配，受限重定向、服务端
  登录校验、账号代次隔离与保留现有 Cookie 的失败路径。

协议参考（实现作者的一手记录；外部接口仍可能变化）：
[bililive-go safeAuth](https://github.com/bililive-go/bililive-go/blob/c5a96e2818ca25d6046ea48812d5e193ecc394fc/src/live/douyu/refresh.go)、
[Biliup 续期说明](https://biliup.github.io/biliup/docs/tutorials/douyu-cookie-guide/)。

## 兼容与验证范围

保留 Windows 小窗配置键，Mac 复用本机设置，不更改备份结构。未登录不自动
登录；手工导入只有 acf_* 时需应用内登录一次才能取得长期票据。失败不清空
旧会话；退出、手工编辑、切换账号与应用关闭必须使在途续期失效。

版本递增为 `3.1.2+4115`。首轮 12 个目标文件共 78 项测试通过；
另补充关闭播放器时原生小窗恢复失败仍释放解码器的回归，完整 652 项 Flutter 测试全部通过（运行阶段 66 秒，总耗时 95.6 秒）。确定性测试、静态检查、构建与真实平台运行分开
记录；未实际运行的平台、真实账号续期和长期播放不得标为已实测。
回滚：撤销本批源码提交；已有账号字段与 Windows 小窗设置保持兼容。


## 实现与交付安排

Mac / Windows 共用播放器和 CompactDanmakuOverlay，不创建第二条视频或弹幕连接。
Mac 使用系统完成事件退出全屏、隐藏窗口按钮并跨桌面显示；返回恢复窗口快照。
重复进入与退出串行化，窗口变化期间不把小窗尺寸写入普通窗口设置。播放器关闭时
即使原生窗口恢复失败也继续释放媒体资源。

每次启动后一次后台 safeAuth 交换，受限重定向、完整字段及登录探针校验后才保存。
长期票据只读取/写入应用 WebView 的 Cookie 存储，不进入配置备份或普通取流头。
服务保留账号版本检查、总截止时间、同次请求合并与手工重试最短间隔。现有手工
Cookie 可继续使用；缺少长期票据时应用内登录一次即可启用后续启动续期。

交付按 Mac → Windows 串行云构建；本机只执行测试与静态检查，不安装或运行应用。
当前无正式 Android 签名 Secrets，本批没有可发布的固定证书 Android APK；
Android / iOS / Linux 的平台更新元数据保持已有版本，不把桌面构建视为移动端交付。
真实斗鱼账号续期、Windows 与 Mac 实际窗口操作尚未采样。


## 质量证据

- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`：0 error、0 warning。
  输出两条既有 Kick/Twitch 风格 info 与一条测试构造形式 info；后者已按提示改为
  initializing formal，由随后完整回归覆盖，没有重复启动整库 Analyze。
- `flutter test --no-pub --concurrency=12`：652 项全部通过，干净源码
  `e4bdbf1d130deb2771a91a6e7a6343a99d9bef0d`。
- changed-file `dart format` 与 `git diff --check` 通过。
- 本机使用 Flutter 3.47.0；Windows 专用 PowerShell 守卫在 Mac 上不可运行，
  因此采用同一 POSIX flock 串行执行并保留 JSON 构建记录。初次受限环境下
  文件读取停顿的测试被终止，`No tests ran` 不计为通过；修正权限后完成上述验证。

- 公共接口探测 39/42 通过；斗鱼推荐、加密描述和搜索通过。两项斗鱼视频链路
  探测遇 TLS 握手失败，CC 分类返回 HTML；探测脚本与基线一致，未使用真实
  登录会话，不据此推定 Cookie 续期失败或声称真实取流全通过。本批继续桌面
  预发布构建，保留外部链路证据缺口。
