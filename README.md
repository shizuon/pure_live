<p align="center">
  <img src="assets/icons/icon.png" width="128" alt="Pure Live 图标">
</p>

<h1 align="center">Pure Live · 双流解说版</h1>

<p align="center">
  看 A 直播间的高清画面，听 B 直播间的解说。
</p>

<p align="center">
  <a href="https://github.com/shizuon/pure_live/actions/workflows/feature-build.yml">
    <img alt="Build" src="https://github.com/shizuon/pure_live/actions/workflows/feature-build.yml/badge.svg">
  </a>
  <a href="LICENSE">
    <img alt="License: AGPL-3.0" src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg">
  </a>
  <a href="https://github.com/liuchuancong/pure_live">
    <img alt="Upstream" src="https://img.shields.io/badge/upstream-liuchuancong%2Fpure__live-lightgrey.svg">
  </a>
</p>

这是 [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live) 的功能性 fork。项目保留上游的多平台直播聚合能力，本仓库只重点维护“替换音频流”：用直播间 A 的画面搭配直播间 B 的声音，主要用于更顺畅地观看主播“玩机器”的直播。

## 双流解说

macOS 是已验证目标；Windows、iOS/iPadOS 已开放迁移测试。进入直播间 A 后，从关注列表中选择在线的直播间 B 作为解说源：

- A 继续提供画面、标题、画质和线路；B 提供声音。
- 校准时可临时查看 B 的画面，对照屏幕时间戳调整。
- 支持 `10ms`、`100ms`、`500ms` 步长，可随时重新校准或更换 B。
- 可选择显示 A 或 B 的弹幕；选择 B 时，弹幕延迟跟随双流偏移。
- B 连接失败时恢复 A 的声音；双流模式不支持录制。

更完整的操作和平台测试说明见[双流解说平台调试与移植](docs/DUAL_COMMENTARY_PLATFORM_DEBUG.md)。

## 维护范围

本仓库的长期维护目标只有双流解说及其直接相关的播放、同步和弹幕问题。

其他问题也可以在本仓库提出，我们会先判断问题属于本 fork 还是上游：

- 有人反馈且上游已经修复的问题，会在确认不破坏双流功能后合并相应修复。
- 平时不主动追随上游的每次提交。上下游都包含较多 AI 辅助改动，维护者没有时间持续逐项审查；未经审查地频繁同步容易引入冲突和回归。
- 范围小、能明确验证的问题，如果在本仓库完成修复，会尽量向上游提交 Pull Request。
- 大型问题、通用功能需求或与双流无关的系统性问题，建议直接提交到[上游 Issues](https://github.com/liuchuancong/pure_live/issues/new/choose)。

提问题时请附上平台、应用版本、直播平台和房间号、复现步骤及日志。请勿公开 Cookie、Token 或其他账号凭据。

## 上游与许可证

- 上游项目：[liuchuancong/pure_live](https://github.com/liuchuancong/pure_live)。本仓库是其衍生版本，不代表上游，也不由上游维护或提供支持。
- 本仓库根目录的 [LICENSE](LICENSE) 是 **GNU Affero General Public License v3.0（AGPL-3.0）** 正文。本 fork 继续以该许可证发布；复制、修改、分发或提供网络服务前，请阅读并遵守许可证原文。
- 原项目和各次修改的著作权归相应贡献者所有。本说明不改变提交历史、版权声明或许可证条款。
- 仓库包含的第三方依赖和内置组件可能使用各自的许可证；相关条款以各组件目录中的 `LICENSE` 及其上游声明为准。
- 这是非官方第三方客户端，与各直播平台没有隶属或授权关系。直播内容、平台名称和商标归各自权利人所有，使用时请遵守所在地法律及平台规则。

以上只是项目关系和仓库现状说明，不是法律意见；许可证权利和义务以 [AGPL-3.0 原文](LICENSE)为准。

## 下载与构建

- 测试包：[本仓库 Releases](https://github.com/shizuon/pure_live/releases)
- 自动构建：[GitHub Actions](https://github.com/shizuon/pure_live/actions)
- 开发、构建和历史测试记录：[文档索引](docs/README.md)
- 旧维护阶段的流程存档：[MAINTENANCE_POLICY.md](MAINTENANCE_POLICY.md)（其中的维护范围已经被本 README 取代）

项目使用 Flutter。工具链版本以 `.fvmrc`、`pubspec.lock` 和平台构建配置为准：

```bash
flutter pub get
flutter test
flutter build macos   # macOS
flutter build windows # Windows（需在 Windows 上执行）
```

## 致谢

感谢 [Pure Live 上游项目](https://github.com/liuchuancong/pure_live)及所有原作者、维护者和贡献者。没有上游工作，就没有这个功能性 fork。
