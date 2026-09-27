import Foundation
import AVFoundation

func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if !condition() { fatalError(label) }
}
for time in [CMTime.invalid, CMTime.indefinite, CMTime.positiveInfinity, CMTime.negativeInfinity] {
    check(BetterPlayerTimeUtils.cmTimeToMillis(time) == 0, "Non-numeric time must be safe")
}
check(BetterPlayerTimeUtils.cmTimeToMillis(CMTime(value: 3003, timescale: 30000)) == 100, "Fractional timestamp")
check(BetterPlayerTimeUtils.cmTimeToMillis(CMTime(value: Int64.max / 2, timescale: 1000)) == Int64.max / 2,
      "Large timestamp must not multiply value by 1000 and overflow")
for interval in [Double.nan, Double.infinity, -Double.infinity, Double.greatestFiniteMagnitude] {
    check(BetterPlayerTimeUtils.timeIntervalToMillis(interval) == 0, "Unbounded interval must not trap")
}
check(BetterPlayerTimeUtils.timeIntervalToMillis(1.234) == 1234, "Finite interval")
check(BetterPlayerTimeUtils.rangeEndMillis(start: CMTime(value: 10, timescale: 1),
      duration: CMTime(value: 5, timescale: 1)) == 15000, "Range endpoint")
_ = BetterPlayerTimeUtils.rangeEndMillis(start: CMTime(value: Int64.max, timescale: 1),
                                        duration: CMTime(value: Int64.max, timescale: 1))
print("iOS AVPlayer time conversions: passed")
