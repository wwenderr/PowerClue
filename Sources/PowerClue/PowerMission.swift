import Foundation

enum MissionAction: String, CaseIterable, Identifiable {
    case lowPowerMode = "Turn on Low Power Mode"
    case pauseApp = "Pause or quit an app"
    case disconnectDisplay = "Disconnect an external display"
    case other = "Make another change"

    var id: Self { self }
    var instruction: String {
        switch self {
        case .lowPowerMode: "Turn on Low Power Mode in System Settings → Battery. PowerClue will detect it."
        case .pauseApp: "Pause or quit one non-essential app. Save your work first; PowerClue will not close it for you."
        case .disconnectDisplay: "Disconnect one external display, then return here."
        case .other: "Make one change that you want to test, then return here."
        }
    }
}

enum MissionPhase: Equatable {
    case ready, baseline, change, after, finished, interrupted
}

struct MissionReading {
    let date: Date
    let watts: Double
    let cpuPercent: Double
}

enum MissionVerdict: Equatable {
    case lower, higher, inconclusive
}

struct MissionResult {
    let beforeWatts: Double
    let afterWatts: Double
    let beforeCPU: Double
    let afterCPU: Double
    let thresholdWatts: Double
    let verdict: MissionVerdict
    let approximateMinutesGained: Int?
    let beforeCount: Int
    let afterCount: Int

    var differenceWatts: Double { beforeWatts - afterWatts }
}

struct PowerMissionState {
    static let settlingSeconds: TimeInterval = 15
    static let measuringSeconds: TimeInterval = 90
    private static let minimumReadings = 8

    private(set) var phase: MissionPhase = .ready
    private(set) var action: MissionAction = .lowPowerMode
    private(set) var stageStartedAt: Date?
    private(set) var baseline: [MissionReading] = []
    private(set) var after: [MissionReading] = []
    private(set) var result: MissionResult?
    private(set) var message: String?
    private var lastReadingAt: Date?
    private var baselineRemainingMinutes: Int?
    private var initialLowPowerMode = false

    var isSampling: Bool { phase == .baseline || phase == .after }

    func progress(at date: Date = Date()) -> Double {
        guard isSampling, let stageStartedAt else { return 0 }
        let total = Self.settlingSeconds + Self.measuringSeconds
        return min(1, max(0, date.timeIntervalSince(stageStartedAt) / total))
    }

    mutating func start(action: MissionAction, battery: BatterySnapshot, system: SystemSnapshot) {
        guard !battery.isOnAC, battery.percent != nil,
              let watts = battery.watts, watts.isFinite, watts > 0, watts < 200,
              action != .lowPowerMode || !system.lowPowerMode else { return }
        self.action = action
        phase = .baseline
        stageStartedAt = battery.timestamp
        baseline = []
        after = []
        result = nil
        message = nil
        lastReadingAt = nil
        baselineRemainingMinutes = battery.minutesRemaining
        initialLowPowerMode = system.lowPowerMode
    }

    mutating func markChanged(battery: BatterySnapshot, system: SystemSnapshot) {
        guard phase == .change, !battery.isOnAC else { return }
        if action == .lowPowerMode && !system.lowPowerMode {
            message = "Turn on Low Power Mode first. PowerClue has not detected it yet."
            return
        }
        phase = .after
        stageStartedAt = battery.timestamp
        after = []
        lastReadingAt = nil
        message = nil
    }

    mutating func record(battery: BatterySnapshot, system: SystemSnapshot) {
        guard isSampling || phase == .change else { return }
        if battery.isOnAC {
            interrupt("The power adapter was connected. Run this test on battery power.")
            return
        }
        guard isSampling else { return }
        guard let stageStartedAt else { return }
        if phase == .baseline && action == .lowPowerMode && system.lowPowerMode != initialLowPowerMode {
            interrupt("Low Power Mode changed during the baseline. Restart and wait until the first measurement ends.")
            return
        }
        if phase == .after && action == .lowPowerMode && !system.lowPowerMode {
            interrupt("Low Power Mode was turned off during the second measurement.")
            return
        }

        let elapsed = battery.timestamp.timeIntervalSince(stageStartedAt)
        if elapsed >= Self.settlingSeconds,
           let watts = battery.watts, watts.isFinite, watts > 0, watts < 200,
           lastReadingAt.map({ battery.timestamp > $0 }) ?? true {
            let reading = MissionReading(date: battery.timestamp, watts: watts, cpuPercent: system.cpuPercent)
            if phase == .baseline { baseline.append(reading) } else { after.append(reading) }
            lastReadingAt = battery.timestamp
            if phase == .baseline && baselineRemainingMinutes == nil {
                baselineRemainingMinutes = battery.minutesRemaining
            }
        }

        guard elapsed >= Self.settlingSeconds + Self.measuringSeconds else { return }
        let count = phase == .baseline ? baseline.count : after.count
        if count < Self.minimumReadings {
            if elapsed >= Self.settlingSeconds + Self.measuringSeconds + 60 {
                interrupt("Not enough valid battery readings were available for a comparison.")
            }
            return
        }
        if phase == .baseline {
            phase = .change
            message = nil
        } else {
            result = Self.evaluate(baseline: baseline, after: after, action: action,
                                   remainingMinutes: baselineRemainingMinutes)
            phase = .finished
        }
        self.stageStartedAt = nil
        lastReadingAt = nil
    }

    mutating func interrupt(_ reason: String) {
        guard isSampling || phase == .change else { return }
        phase = .interrupted
        stageStartedAt = nil
        message = reason
    }

    mutating func reset() { self = PowerMissionState() }

    static func evaluate(baseline: [MissionReading], after: [MissionReading], action: MissionAction,
                         remainingMinutes: Int?) -> MissionResult {
        let beforeWatts = median(baseline.map(\.watts))
        let afterWatts = median(after.map(\.watts))
        let beforeSpread = median(baseline.map { abs($0.watts - beforeWatts) })
        let afterSpread = median(after.map { abs($0.watts - afterWatts) })
        let threshold = max(0.8, max(beforeSpread, afterSpread) * 2, beforeWatts * 0.06)
        let tooVariable = max(beforeSpread / max(beforeWatts, 1),
                              afterSpread / max(afterWatts, 1)) > 0.18
        let beforeCPU = average(baseline.map(\.cpuPercent))
        let afterCPU = average(after.map(\.cpuPercent))
        let workloadShifted = action != .pauseApp && abs(afterCPU - beforeCPU) > 20
        let difference = beforeWatts - afterWatts
        let verdict: MissionVerdict = tooVariable || workloadShifted || abs(difference) <= threshold ? .inconclusive :
            (difference > 0 ? .lower : .higher)
        let minutes: Int?
        if verdict == .lower, let remainingMinutes, remainingMinutes > 0, afterWatts > 0 {
            let estimate = Double(remainingMinutes) * (beforeWatts / afterWatts - 1)
            minutes = estimate.isFinite && estimate >= 1 && estimate <= 720 ? Int(estimate.rounded()) : nil
        } else {
            minutes = nil
        }
        return MissionResult(beforeWatts: beforeWatts, afterWatts: afterWatts,
                             beforeCPU: beforeCPU,
                             afterCPU: afterCPU,
                             thresholdWatts: threshold, verdict: verdict,
                             approximateMinutesGained: minutes,
                             beforeCount: baseline.count, afterCount: after.count)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
