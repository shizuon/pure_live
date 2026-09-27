# 3.1.1 iOS进入直播间闪退排查

用户反馈IJK和标为Exo的内核在iOS进入直播间直接闪退。基线 `ee166c1d`；
原生源码均已在3.1.0业务提交 `df46251f` 存在。暂未获得设备 `.ips` 崩溃栈，
故具体故障为 `not-reproduced`，不能用Dart测试宣称原生崩溃已实机修复。

代码确认的候选缺陷：

- iOS上“Exo”实际为BetterPlayer的AVPlayer后端，名称混用了Android后端。
- IJK原生初始化设置 `fcc-bgra`，Dart公共配置又写入Android风格
  `overlay-format=0x52474238`，缺少平台区分。
- IJK的像素缓冲回调对null无保护，重复同一buffer只在首次retain，Flutter取走
  latest后仍继续复用；lastBuffer和latest交换/释放跨线程，引用生命周期不一致。
- BetterPlayer对所有URL视频异步设置AVMutableVideoComposition，包括无穷时长
  直播；旧异步回调只检查disposed，不检查当前item；KVO删除依赖currentItem，
  可能不同于最初注册对象。时间换算 `value*1000` 可溢出，NaN转Int64会trap。

保留IJK与AVPlayer选择，不靠隐藏入口宣称修复；iOS新安装默认MediaKit，
已有明确选择保留。修复IJK格式/像素引用，AVPlayer时长/异步/观察者生命周期。
已知FLV/RTMP输入在iOS AVPlayer原生调用前报可恢复错误，沿已有引擎回退。
不换媒体库、不操作用户设备或签名。3.1.0资产不变，修复并入未发布的3.1.1。

验证须分开记录：Dart策略、生产原生工具测试、云端iOS编译和IPA核验；
仍需设备崩溃栈和同房间实测确认实际根因。

## 已实施与验证

- IJK像素交付改用生产 `FijkPixelBufferMailbox`：每次发布独立retain，
  互斥交换pending、Flutter取走引用、覆盖/close释放，忽略null和退出后的回调。
  帧通知切主线程，不持有强self导致退出后播放器泄漏。
- iOS IJK保持原生要求的BGRA格式，只写VideoToolbox配置；Android保留
  MediaCodec及原RGB配置。User-Agent设置等待完成再准备流。
- BetterPlayer时间工具对invalid/indefinite/infinity返回不可用值0，
  CoreMedia负责缩放及范围相加，避免整数溢出或浮点转整数trap。
  常规方向不套额外合成；直播无穷时长不走VOD合成路径。
- KVO追踪原注册item，换源前移除；旧异步转换通过代次和item身份隔离，
  UI/AVPlayerItem赋值回主线程；销毁真正调用dispose、移除媒体项和事件Sink，
  不再只clear，延时stall检查取消。
- iOS菜单“Exo”更名AVPlayer，存储key保持exo兼容旧设置。已知FLV/RTMP在
  原生调用前报可恢复错误，交给现有内核回退。默认仅新配置改MediaKit，
  旧用户明确选项不自动覆盖；不谎称AVPlayer已支持FLV。

25项定向Dart测试通过，最后完整回归 **612项全部通过**（61秒运行阶段）。
lib/test分析0 error / 0 warning，仅Kick/Twitch两条既有风格info。
`tool/test_ios_engine_safety.sh` 实际编译生产时间工具和像素mailbox：
无穷/非法/超大时间、重复同地址1000次帧交付、并发发布/消费及close保护均通过。
另对两份Swift插件文件运行语法解析；完整UIKit/Flutter类型检查仍由iOS云编译负责。
Apple构建工作流加入同一工具测试，不能只靠Dart测试证明原生补丁正确。

原Mac候选run `36327981449` 不含iOS补丁，将取消；最终交付改为iOS优先，
之后Mac→Android→Windows→Linux串行。版本仍为未发布批次3.1.1+4114。
3.1.0已发布资产不修改。没有安装/运行应用或操作设备。

最终业务提交 `fdac378815c3231eb9d6e818efdf0308fbb5c7fc` 已快进推送master和
`feat/platform-quality-login-20260926`。旧Mac run36327981449已取消；
[iOS优先构建36330643128](https://github.com/shizuon/pure_live/actions/runs/36330643128)
已启动完整质量检查、Apple工具测试和iOS编译，当前未完成IPA交付。
自动化 `pure-live-3-1-1` 继续跟进iOS核验后其他平台，最终候选不混用旧Mac包。
