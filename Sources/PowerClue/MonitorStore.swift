import AppKit
import Combine
import Darwin
import Foundation

private struct SampleResult {
    var battery: BatterySnapshot
    var system: SystemSnapshot
    var processes: [ProcessSnapshot]
    var assertions: [PowerAssertion]
    var history: [HistorySample]?
    var current: HistorySample
    var drainBaseline: Double?
}

private final class SamplePipeline: @unchecked Sendable {
    // Every method is called on the monitor's one serial collector queue.
    let battery = BatteryCollector()
    let system = SystemCollector()
    let processes = ProcessCollector()
    let network = NetworkCollector()
    let assertions = PowerAssertionCollector()
    let sleepLog = SleepLogParser()
    let history = HistoryStore()
    private var lastNetwork = Date.distantPast
    private var lastAssertions = Date.distantPast
    private var networkRates: [Int32: NetworkRates] = [:]
    private var powerAssertions: [PowerAssertion] = []
    private var baseline: Double?
    private var lastBaseline = Date.distantPast

    func sample(range: HistoryRange, includeHistory: Bool) -> SampleResult {
        let now = Date()
        var batterySnapshot = battery.sample()
        var systemSnapshot = system.sample()
        var processSnapshots = processes.sample()
        if now.timeIntervalSince(lastNetwork) >= 10 {
            networkRates = network.sample()
            lastNetwork = Date()
        }
        if now.timeIntervalSince(lastAssertions) >= 10 {
            powerAssertions = assertions.sample()
            lastAssertions = Date()
        }
        let preventing = Set(powerAssertions.filter(\.preventsSleep).map(\.pid))
        for index in processSnapshots.indices {
            let pid = processSnapshots[index].pid
            if let rates = networkRates[pid] {
                processSnapshots[index].networkInPerSecond = rates.incoming
                processSnapshots[index].networkOutPerSecond = rates.outgoing
                processSnapshots[index].networkSignal = min(10, (rates.incoming + rates.outgoing) / 1_000_000)
            }
            processSnapshots[index].preventsSleep = preventing.contains(pid)
            processSnapshots[index].impact = Int(min(100,
                processSnapshots[index].cpuSignal + processSnapshots[index].wakeupSignal +
                processSnapshots[index].diskSignal + processSnapshots[index].networkSignal))
        }
        processSnapshots.sort { $0.impact == $1.impact ? $0.cpuPercent > $1.cpuPercent : $0.impact > $1.impact }
        systemSnapshot.networkInPerSecond = networkRates.values.reduce(0) { $0 + $1.incoming }
        systemSnapshot.networkOutPerSecond = networkRates.values.reduce(0) { $0 + $1.outgoing }
        systemSnapshot.diskReadPerSecond = processSnapshots.reduce(0) { $0 + ($1.diskReadPerSecond ?? 0) }
        systemSnapshot.diskWritePerSecond = processSnapshots.reduce(0) { $0 + ($1.diskWritePerSecond ?? 0) }
        // Keep the sample time after slower collectors have finished.
        batterySnapshot.timestamp = Date()
        let sample = HistorySample(date: batterySnapshot.timestamp,
                                   batteryPercent: batterySnapshot.percent,
                                   batteryWatts: batterySnapshot.watts,
                                   drainPerHour: batterySnapshot.drainPerHour,
                                   cpuPercent: systemSnapshot.cpuPercent,
                                   memoryUsed: systemSnapshot.memoryUsed,
                                   swapUsed: systemSnapshot.swapUsed,
                                   networkInPerSecond: systemSnapshot.networkInPerSecond,
                                   networkOutPerSecond: systemSnapshot.networkOutPerSecond,
                                   diskReadPerSecond: systemSnapshot.diskReadPerSecond,
                                   diskWritePerSecond: systemSnapshot.diskWritePerSecond,
                                   thermalState: systemSnapshot.thermalState,
                                   topProcess: processSnapshots.first?.name,
                                   topCPU: processSnapshots.first?.cpuPercent,
                                   topProcesses: Array(processSnapshots.prefix(5)))
        history.append(sample)
        if now.timeIntervalSince(lastBaseline) > 600 {
            baseline = history.drainBaseline()
            lastBaseline = now
        }
        return SampleResult(battery: batterySnapshot, system: systemSnapshot,
                            processes: processSnapshots, assertions: powerAssertions,
                            history: includeHistory
                                ? history.samples(since: Date().addingTimeInterval(-range.seconds),
                                                  bucketSeconds: range.bucketSeconds)
                                : nil,
                            current: sample,
                            drainBaseline: baseline)
    }

    func history(for range: HistoryRange) -> [HistorySample] {
        history.samples(since: Date().addingTimeInterval(-range.seconds), bucketSeconds: range.bucketSeconds)
    }

    func saveSleep(_ session: SleepSession) { history.save(session) }

    func completeSleep(_ session: SleepSession) -> [SleepSession] {
        var updated = session
        updated.end = Date()
        updated.endingBattery = battery.sample().percent
        if let end = updated.end {
            let events = sleepLog.events(from: updated.start, to: end)
            updated.darkWakes = events.darkWakes
            updated.wakeEvents = events.wakeEvents
            updated.networkWakes = events.networkWakes
            updated.scheduledWakes = events.scheduledWakes
            updated.wakeReasons = events.reasons
        }
        history.save(updated)
        return history.sleepSessions()
    }

    func storedSessions() -> [SleepSession] { history.sleepSessions() }
}

@MainActor
final class MonitorStore: ObservableObject {
    @Published private(set) var battery = BatterySnapshot()
    @Published private(set) var system = SystemSnapshot()
    @Published private(set) var processes: [ProcessSnapshot] = []
    @Published private(set) var assertions: [PowerAssertion] = []
    @Published private(set) var history: [HistorySample] = []
    @Published private(set) var sleepSessions: [SleepSession] = []
    @Published private(set) var selfMonitoringWarning = false
    @Published private(set) var drainBaseline: Double?
    @Published private(set) var mission = PowerMissionState()
    @Published var selectedSection: Section = .overview {
        didSet {
            if sectionNeedsHistory { loadHistory() }
        }
    }
    @Published var selectedProcess: Int32?
    @Published var search = ""
    @Published var historyRange: HistoryRange = .oneHour {
        didSet { loadHistory() }
    }

    private let collectorQueue = DispatchQueue(label: "app.powerclue.collectors", qos: .utility)
    private let pipeline = SamplePipeline()
    private var timer: Timer?
    private var collecting = false
    private var isSleeping = false
    private var visibleSurfaces = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var activeSleep: SleepSession?
    private var recentSamples: [HistorySample] = []
    private var highSelfCPUCount = 0
    private var pressureSource: (any DispatchSourceMemoryPressure)?
    private var memoryPressureState = "No warning observed"

    init() {
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self, weak pressure] in
            guard let pressure else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let event = pressure.data
                self.memoryPressureState = event.contains(.critical) ? "Critical" :
                    (event.contains(.warning) ? "Elevated" : "Normal")
                self.system.memoryPressure = self.memoryPressureState
            }
        }
        pressure.resume()
        pressureSource = pressure
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.beginSleep() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.endSleep() }
        })
        scheduleTimer()
        refresh()
        let pipeline = self.pipeline
        collectorQueue.async { [weak self] in
            let sessions = pipeline.storedSessions()
            Task { @MainActor [weak self] in self?.sleepSessions = sessions }
        }
    }

    deinit {
        timer?.invalidate()
        pressureSource?.cancel()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    var topProcess: ProcessSnapshot? { processes.first }
    private var sectionNeedsHistory: Bool {
        selectedSection == .battery || selectedSection == .performance || selectedSection == .history
    }
    var selectedProcessDetail: ProcessSnapshot? { processes.first { $0.pid == selectedProcess } }
    var filteredProcesses: [ProcessSnapshot] {
        guard !search.isEmpty else { return processes }
        return processes.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            ($0.applicationName?.localizedCaseInsensitiveContains(search) ?? false) ||
            String($0.pid).contains(search)
        }
    }

    var diagnosis: String {
        if system.thermalState == "Critical" || system.thermalState == "Serious" {
            return "Thermal pressure may be reducing performance."
        }
        if system.memoryPressure == "Elevated" || system.memoryPressure == "Critical" {
            let names = processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(2).map(\.name).joined(separator: " and ")
            return "macOS reported \(system.memoryPressure.lowercased()) memory pressure. \(names) currently have the largest memory footprints."
        }
        if let process = processes.first(where: { ($0.wakeupsPerSecond ?? 0) > 20 }) {
            return "\(process.name) is waking the CPU unusually often (\(Int((process.wakeupsPerSecond ?? 0) * 60))/min). This can increase battery use."
        }
        let recentMinute = recentSamples.filter { Date().timeIntervalSince($0.date) <= 60 }
        if recentMinute.count >= 8,
           recentMinute.map(\.cpuPercent).reduce(0, +) / Double(recentMinute.count) > 70,
           let process = processes.max(by: { $0.cpuPercent < $1.cpuPercent }) {
            return "CPU has stayed busy for about a minute. \(process.name) is currently using \(formatCPUPercent(process.cpuPercent))."
        }
        if let drain = battery.averageDrain5m, drain > 0, !battery.isOnAC {
            if let baseline = drainBaseline, baseline > 0, drain / baseline >= 1.5 {
                return "Battery drain is about \(String(format: "%.1f", drain / baseline))× your recent baseline. The process list shows possible contributors, not measured shares."
            }
            return "Battery is draining at about \(drain.formatted(.number.precision(.fractionLength(1))))%/h over five minutes. The process list shows possible contributors, not measured shares."
        }
        return "Live activity is being monitored. Check Battery for possible contributors and History for trends."
    }

    func setVisible(_ visible: Bool) {
        visibleSurfaces = max(0, visibleSurfaces + (visible ? 1 : -1))
        scheduleTimer()
    }

    func startMission(_ action: MissionAction) {
        mission.start(action: action, battery: battery, system: system)
        scheduleTimer()
    }

    func markMissionChange() {
        mission.markChanged(battery: battery, system: system)
        scheduleTimer()
    }

    func resetMission() {
        mission.reset()
        scheduleTimer()
    }

    func refresh() {
        guard !collecting && !isSleeping else { return }
        collecting = true
        let pipeline = self.pipeline
        let range = historyRange
        let includeHistory = sectionNeedsHistory
        collectorQueue.async { [weak self] in
            let result = pipeline.sample(range: range, includeHistory: includeHistory)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.battery = result.battery
                self.system = result.system
                self.system.memoryPressure = self.memoryPressureState
                self.processes = result.processes
                self.assertions = result.assertions
                self.drainBaseline = result.drainBaseline
                if self.historyRange == range, let history = result.history { self.history = history }
                self.recentSamples.append(result.current)
                self.recentSamples.removeAll { Date().timeIntervalSince($0.date) > 3600 }
                self.mission.record(battery: self.battery, system: self.system)
                if let selfProcess = result.processes.first(where: { $0.pid == getpid() }), selfProcess.cpuPercent > 5 {
                    self.highSelfCPUCount += 1
                } else { self.highSelfCPUCount = 0 }
                self.selfMonitoringWarning = self.highSelfCPUCount >= 5
                self.collecting = false
                self.scheduleTimer()
            }
        }
    }

    func loadHistory() {
        let pipeline = self.pipeline
        let range = historyRange
        collectorQueue.async { [weak self] in
            let samples = pipeline.history(for: range)
            Task { @MainActor [weak self] in
                if self?.historyRange == range { self?.history = samples }
            }
        }
    }

    private func scheduleTimer() {
        guard !isSleeping else { timer?.invalidate(); timer = nil; return }
        let interval: TimeInterval = visibleSurfaces > 0 ? 3 : (mission.isSampling ? 5 : (system.lowPowerMode ? 12 : 5))
        if let timer, timer.isValid, abs(timer.timeInterval - interval) < 0.01 { return }
        timer?.invalidate()
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        next.tolerance = interval * 0.2
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func beginSleep() {
        guard !isSleeping else { return }
        mission.interrupt("The Mac went to sleep during the test. Start again when it is awake.")
        isSleeping = true
        scheduleTimer()
        let session = SleepSession(start: Date(), startingBattery: battery.percent,
                                   priorProcesses: Array(processes.prefix(5).map(\.name)),
                                   priorAssertions: assertions,
                                   priorBatteryWatts: battery.watts,
                                   priorDrainPerHour: battery.drainPerHour,
                                   priorNetworkInPerSecond: system.networkInPerSecond,
                                   priorNetworkOutPerSecond: system.networkOutPerSecond,
                                   priorThermalState: system.thermalState)
        activeSleep = session
        let pipeline = self.pipeline
        collectorQueue.sync { pipeline.saveSleep(session) }
    }

    private func endSleep() {
        guard isSleeping else { return }
        isSleeping = false
        scheduleTimer()
        refresh()
        guard let session = activeSleep else { return }
        activeSleep = nil
        let pipeline = self.pipeline
        collectorQueue.async { [weak self] in
            let sessions = pipeline.completeSleep(session)
            Task { @MainActor [weak self] in self?.sleepSessions = sessions }
        }
    }
}
