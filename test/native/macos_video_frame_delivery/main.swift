import CoreGraphics
import Foundation

// Exercise requests that have reached production VideoOutput and Worker with
// a controllable renderer. The mpv-to-main-thread callback trampoline remains
// outside this harness; no Flutter engine or live stream is involved.
public protocol ResizableTextureProtocol: AnyObject {
  func resize(_ size: CGSize)
  func render(_ size: CGSize)
}

public protocol FlutterTextureRegistry {
  func register(_ texture: ResizableTextureProtocol) -> Int64
  func unregisterTexture(_ textureId: Int64)
  func textureFrameAvailable(_ textureId: Int64)
}

struct VideoOutputConfiguration {
  let width: Int64? = 640
  let height: Int64? = 360
  let enableHardwareAcceleration = true
}

enum MPVHelpers {
  static func getVideoOutParams(_ handle: OpaquePointer) ->
    (rotate: Int64, dw: Int64, dh: Int64) { (0, 640, 360) }
}

final class RenderProbe {
  let rendered = DispatchSemaphore(value: 0)
  let resume = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var shouldBlock = false
  private var renderCount = 0

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return renderCount
  }

  func blockNextRender() {
    lock.lock()
    shouldBlock = true
    lock.unlock()
  }

  func render() {
    lock.lock()
    renderCount += 1
    let block = shouldBlock
    shouldBlock = false
    lock.unlock()
    rendered.signal()
    if block { resume.wait() }
  }
}

let probe = RenderProbe()

class TextureHW: NSObject, ResizableTextureProtocol {
  init(handle: OpaquePointer, updateCallback: @escaping () -> Void) {}
  func resize(_ size: CGSize) {}
  func render(_ size: CGSize) { probe.render() }
}

typealias TextureSW = TextureHW

final class SafeResizableTexture: NSObject, ResizableTextureProtocol {
  let child: ResizableTextureProtocol
  init(_ child: ResizableTextureProtocol) { self.child = child }
  func resize(_ size: CGSize) { child.resize(size) }
  func render(_ size: CGSize) { child.render(size) }
}

final class Registry: FlutterTextureRegistry {
  var registered = false
  var notifications = 0
  var unregistered = false

  func register(_ texture: ResizableTextureProtocol) -> Int64 {
    precondition(Thread.isMainThread)
    registered = true
    return 42
  }
  func unregisterTexture(_ textureId: Int64) {
    precondition(Thread.isMainThread && textureId == 42)
    unregistered = true
  }
  func textureFrameAvailable(_ textureId: Int64) {
    precondition(Thread.isMainThread && registered && !unregistered && textureId == 42)
    notifications += 1
  }
}

func pumpMain(until condition: () -> Bool) {
  let deadline = Date().addingTimeInterval(2)
  while !condition() && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.005))
  }
  precondition(condition(), "Platform-thread delivery timed out")
}

func awaitRender() {
  precondition(
    probe.rendered.wait(timeout: .now() + 2) == .success,
    "A queued render waited for the blocked platform thread"
  )
}

let registry = Registry()
var output: VideoOutput? = VideoOutput(
  handle: 1,
  configuration: VideoOutputConfiguration(),
  registry: registry,
  textureUpdateCallback: { _, _ in precondition(Thread.isMainThread) }
)
pumpMain { registry.registered }

// A slow render followed by a burst must leave only the newest pending update.
probe.blockNextRender()
output!.updateCallback()
awaitRender()
for _ in 0..<1000 { output!.updateCallback() }
probe.resume.signal()
awaitRender()
precondition(probe.rendered.wait(timeout: .now() + 0.1) == .timedOut)
precondition(probe.count == 2 && registry.notifications == 0)
pumpMain { registry.notifications == 1 }

// Requests already delivered to VideoOutput progress while the main thread is
// occupied, and their notifications coalesce until Flutter consumes a frame.
for _ in 0..<3 {
  output!.updateCallback()
  awaitRender()
}
precondition(probe.count == 5 && registry.notifications == 1)
pumpMain { registry.notifications == 2 }

// Closing during an active render releases the texture after the worker exits,
// without delivering a notification for an unregistered texture.
probe.blockNextRender()
output!.updateCallback()
awaitRender()
output = nil
probe.resume.signal()
pumpMain { registry.unregistered }
print("macOS frame delivery: queued-render progress, burst coalescing, notification delivery and active-render disposal passed")
