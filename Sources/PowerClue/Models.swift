import Foundation

enum Section: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processes = "Processes"
    case battery = "Battery"
    case mission = "Mission"
    case performance = "Performance"
    case sleep = "Sleep"
    case history = "History"
    case settings = "Settings"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .overview: "house.fill"
        case .processes: "square.grid.2x2.fill"
        case .battery: "battery.75percent"
        case .mission: "scope"
        case .performance: "chart.xyaxis.line"
        case .sleep: "moon.zzz.fill"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape.fill"
        }
    }
}

struct BatterySnapshot: Codable {
    var percent: Int?
    var isCharging = false
    var isOnAC = false
    var minutesRemaining: Int?
    var watts: Double?
    var averageWatts1m: Double?
    var averageWatts5m: Double?
    var averageWatts15m: Double?
    var drainPerHour: Double?
    var averageDrain1m: Double?
    var averageDrain5m: Double?
    var averageDrain15m: Double?
    var timestamp = Date()
}

struct SystemSnapshot: Codable {
    var cpuPercent: Double = 0
    var userCPU: Double = 0
    var systemCPU: Double = 0
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var swapUsed: UInt64 = 0
    var memoryPressure: String = "No warning observed"
    var thermalState: String = "—"
    var loadAverage: Double = 0
    var diskReadPerSecond: Double = 0
    var diskWritePerSecond: Double = 0
    var networkInPerSecond: Double = 0
    var networkOutPerSecond: Double = 0
    var lowPowerMode = false
}

struct ProcessSnapshot: Identifiable, Codable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var applicationName: String? = nil
    var parentPID: Int32? = nil
    var cpuPercent: Double = 0
    var cpuSeconds: Double = 0
    var cpuPowerWatts: Double? = nil
    var memoryBytes: UInt64 = 0
    var wakeupsPerSecond: Double? = nil
    var diskReadPerSecond: Double? = nil
    var diskWritePerSecond: Double? = nil
    var networkInPerSecond: Double? = nil
    var networkOutPerSecond: Double? = nil
    var preventsSleep = false
    var cpuSignal: Double = 0
    var wakeupSignal: Double = 0
    var diskSignal: Double = 0
    var networkSignal: Double = 0
    var impact: Int = 0

    var impactLabel: String {
        switch impact {
        case 70...: "Very active"
        case 40...: "Elevated"
        case 15...: "Some activity"
        default: "Quiet"
        }
    }
    var reasons: [String] {
        var result: [String] = []
        if cpuSignal >= 2 { result.append("CPU \(formatCPUPercent(cpuPercent))") }
        if wakeupSignal >= 2, let wakeupsPerSecond { result.append("wakeups \(Int(wakeupsPerSecond * 60))/min") }
        let diskTotal = (diskReadPerSecond ?? 0) + (diskWritePerSecond ?? 0)
        if diskSignal >= 2 { result.append("disk I/O \(formatRate(diskTotal))") }
        let networkTotal = (networkInPerSecond ?? 0) + (networkOutPerSecond ?? 0)
        if networkSignal >= 2 { result.append("network \(formatRate(networkTotal))") }
        if preventsSleep { result.append("prevents sleep") }
        return result.isEmpty ? ["No notable activity signals right now"] : result
    }
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case fiveMinutes = "5m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case sixHours = "6h"
    case oneDay = "24h"

    var id: Self { self }
    var seconds: TimeInterval {
        switch self {
        case .fiveMinutes: 300
        case .thirtyMinutes: 1800
        case .oneHour: 3600
        case .sixHours: 21600
        case .oneDay: 86400
        }
    }
    var bucketSeconds: Int { max(1, Int(seconds / 360)) }
}

struct HistorySample: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var batteryPercent: Int?
    var batteryWatts: Double? = nil
    var drainPerHour: Double? = nil
    var cpuPercent: Double
    var memoryUsed: UInt64
    var swapUsed: UInt64 = 0
    var networkInPerSecond: Double = 0
    var networkOutPerSecond: Double = 0
    var diskReadPerSecond: Double = 0
    var diskWritePerSecond: Double = 0
    var thermalState: String = "Nominal"
    var topProcess: String?
    var topCPU: Double?
    var topProcesses: [ProcessSnapshot] = []
}

struct PowerAssertion: Codable, Identifiable {
    var id: String { "\(pid)-\(type)-\(name)" }
    var pid: Int32
    var processName: String
    var type: String
    var name: String
    var preventsSleep: Bool {
        type.contains("PreventUserIdleSystemSleep") ||
        type.contains("PreventSystemSleep") ||
        type.contains("NoIdleSleep")
    }
}

struct SleepSession: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date?
    var startingBattery: Int?
    var endingBattery: Int?
    var priorProcesses: [String]
    var priorAssertions: [PowerAssertion] = []
    var priorBatteryWatts: Double? = nil
    var priorDrainPerHour: Double? = nil
    var priorNetworkInPerSecond: Double = 0
    var priorNetworkOutPerSecond: Double = 0
    var priorThermalState: String = "Unknown"
    var darkWakes: Int = 0
    var wakeEvents: Int = 0
    var networkWakes: Int = 0
    var scheduledWakes: Int = 0
    var wakeReasons: [String] = []

    var batteryLoss: Int? {
        guard let startingBattery, let endingBattery else { return nil }
        return startingBattery - endingBattery
    }
    var hours: Double { max(0, (end ?? Date()).timeIntervalSince(start) / 3600) }
    var drainPerHour: Double? {
        guard let batteryLoss, hours > 0 else { return nil }
        return Double(batteryLoss) / hours
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
}

func formatRate(_ bytes: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)), countStyle: .file) + "/s"
}

func formatCPUPercent(_ percent: Double) -> String {
    guard percent.isFinite, percent > 0 else { return "0%" }
    if percent < 0.1 { return "<0.1%" }
    if percent < 10 { return String(format: "%.1f%%", percent) }
    return String(format: "%.0f%%", percent)
}

func formatCPUWatts(_ watts: Double?) -> String {
    guard let watts, watts.isFinite, watts >= 0 else { return "—" }
    if watts > 0 && watts < 0.001 { return "<0.001 W" }
    if watts < 0.1 { return String(format: "%.3f W", watts) }
    if watts < 10 { return String(format: "%.2f W", watts) }
    return String(format: "%.1f W", watts)
}
