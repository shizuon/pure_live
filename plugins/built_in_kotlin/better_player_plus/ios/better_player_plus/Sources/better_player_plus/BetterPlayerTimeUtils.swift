import Foundation
import AVFoundation

public enum BetterPlayerTimeUtils {
    public static func cmTimeToMillis(_ time: CMTime) -> Int64 {
        guard time.isValid, time.isNumeric, time.timescale > 0 else { return 0 }
        let scaled = CMTimeConvertScale(time, timescale: 1000, method: .roundTowardZero)
        guard scaled.isValid, scaled.isNumeric else { return 0 }
        return scaled.value
    }

    public static func timeIntervalToMillis(_ interval: TimeInterval) -> Int64 {
        let value = interval * 1000.0
        guard value.isFinite, value < Double(Int64.max), value >= Double(Int64.min) else { return 0 }
        return Int64(value)
    }

    public static func rangeEndMillis(start: CMTime, duration: CMTime) -> Int64 {
        // Sum in CoreMedia, not in Swift Int64 where live timestamp sentinels
        // and extreme ranges can produce a release-mode overflow trap.
        return cmTimeToMillis(CMTimeAdd(start, duration))
    }
}
