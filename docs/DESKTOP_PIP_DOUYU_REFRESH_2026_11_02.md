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


## 云构建受阻（2026-11-02）

源码已推送 `master` 与 `feat/desktop-pip-douyu-refresh-20261102`，首次候选提交
`e18074c`。两次 Mac workflow_dispatch 均在创建 Run 前被 GitHub 拒绝：
`HTTP 422: Actions has been disabled for this repository.`

只读核对显示仓库未归档、未禁用，Actions permissions 为 `enabled: true`，
`feature-build.yml` 为 `active`。对该工作流调用 enable 返回成功后重试仍为 422。
没有构建 Run、没有新安装包、没有创建 3.1.2 Release，也没有更改账户计费设置。
GitHub 文档说明这种提示可能来自平台控制的独立禁用状态，需要联系支持审查；
现有 API 证据不足以判断具体原因，不把它归因于余额或账号违规。

[GitHub 官方说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)。

应用更新清单 `assets/version.json` 暂时保持之前的已存在状态，避免把未产出的
3.1.2 安装包当作可下载更新。源码候选仍为 `3.1.2+4115`；实际构建/发布恢复时
再同步本次交付的平台条目。当前未改动历史 Release 与 `assets/releases.json`。

进一步对斗鱼公共链路做一次分阶段检查：主站加密描述 GET 和 H5 取流 POST
成功，失败出现在返回的视频 CDN TLS 握手。该探测不含账号凭据，不证明真实
登录 Cookie 续期已完成，也不把这个网络结果与确定性状态机测试混为一谈。


### 凭据复核与网页提示补充

2026-11-02 11:42 UTC 重新核对实际请求：`GET /user` 返回 `shizuon`，
仓库 `admin: true`，服务端返回令牌范围 `repo, workflow`（另有 gist/read:org）。
环境没有 GH_TOKEN/GITHUB_TOKEN 覆盖，明确提取 shizuon 凭据并清空可能覆盖项后，
直接 POST workflow dispatch 仍返回相同 HTTP 422。不能将此次失败归为账号用错
或缺少 workflow scope。

随后实际打开仓库 [Actions 页面](https://github.com/shizuon/pure_live/actions)，
页面说明：此 fork 的工作流因 GitHub Actions 用量规模被暂停，维护者可以重新启用。
这比先前 API 的泛化错误更具体。工作流 enable 与重新提交原有仓库 Actions
permissions 都未消除该提示；后者前后仍为 enabled=true/allowed_actions=all，
没有扩大权限。下一步应由已登录的仓库维护者通过网页的重新启用入口恢复，
不需要先换令牌或修改付费预算。若网页恢复也失败，再依据实际提示联系支持。
当前自动化浏览器未登录，尚未完成这项网页操作，也没有新构建 Run。


### 用户恢复后继续交付

用户已确认在网页完成重新启用，继续本轮 Mac → Windows 云构建。
候选分支恢复 3.1.2 桌面版本清单，业务代码与已通过 652 项回归的提交一致；
暂不将该清单推送 master，等对应安装包真正发布后再同步更新公告。


### 恢复后的运行机容量问题

Mac Run [41439471208](https://github.com/shizuon/pure_live/actions/runs/41439471208)
成功创建，但等待约 15 分钟后由 GitHub 结束，未执行任何构建步骤。
Check annotation 明确报告 hosted runner 多次领取失败，以及 macOS arm64
运行机容量不足；这与此前 fork 禁用状态不同。

将 Apple job 改为官方支持的 `macos-15-intel`，仍使用 macOS 15 / Xcode 26
和 Flutter 3.47.0；安装包继续要求 `x86_64`、`arm64` 两种架构。
业务源码和依赖未改动，复用 `e4bdbf1` 的完整 652 项回归；重新进行目标平台
构建和产物核验，不把更换运行机当作已成功打包。
