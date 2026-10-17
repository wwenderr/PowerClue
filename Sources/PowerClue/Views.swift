import AppKit
import Charts
import SwiftUI

private enum Palette {
    static let background = Color(red: 0.045, green: 0.065, blue: 0.09)
    static let card = Color(red: 0.075, green: 0.105, blue: 0.135)
    static let border = Color.white.opacity(0.085)
    static let secondary = Color(red: 0.64, green: 0.69, blue: 0.75)
    static let blue = Color(red: 0.23, green: 0.49, blue: 1)
    static let red = Color(red: 1, green: 0.30, blue: 0.26)
}

private struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border))
    }
}

private struct Metric: View {
    let title: String
    let value: String
    let subtitle: String?
    let color: Color

    init(_ title: String, value: String, subtitle: String? = nil, color: Color = .white) {
        self.title = title; self.value = value; self.subtitle = subtitle; self.color = color
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(Palette.secondary)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProgressMetric: View {
    let title: String
    let value: Double
    let color: Color
    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 68, alignment: .leading)
            Text("\(Int(value))%").monospacedDigit().frame(width: 38, alignment: .trailing)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, value / 100)))
                }
            }
            .frame(height: 8)
        }
        .font(.caption)
    }
}

struct MenuDashboard: View {
    @EnvironmentObject private var monitor: MonitorStore
    @Environment(\.openWindow) private var openWindow
    @State private var openDashboardHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: monitor.battery.isOnAC ? "bolt.fill" : "battery.75percent")
                    .foregroundStyle(.green)
                Text(monitor.battery.percent.map { "\($0)%" } ?? "No battery")
                    .font(.headline)
                Spacer()
                Text(monitor.battery.isOnAC ? "Power adapter" : remainingText)
                    .foregroundStyle(Palette.secondary)
                    .font(.caption)
            }
            Divider()
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(Palette.red)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(monitor.topProcess?.impact ?? 0 >= 40 ? "Elevated process activity" : "Current status")
                        .font(.headline)
                    Text(monitor.diagnosis).font(.caption).foregroundStyle(Palette.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            ProgressMetric(title: "CPU", value: monitor.system.cpuPercent, color: .orange)
            ProgressMetric(title: "Memory", value: memoryPercent, color: Palette.blue)
            Text("ACTIVITY RELATED TO BATTERY USE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 4)
            ForEach(monitor.processes.prefix(3)) { process in
                HStack {
                    Text(process.name).lineLimit(1)
                    Spacer()
                    Text(process.impactLabel).foregroundStyle(impactColor(process.impact))
                    Text(formatCPUPercent(process.cpuPercent))
                        .monospacedDigit().frame(width: 34, alignment: .trailing)
                }
                .font(.caption)
            }
            Text("Possible contributors from CPU, wakeups and disk; ranking is not total watts.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.secondary)
            Divider()
            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open dashboard", systemImage: "rectangle.expand.vertical")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(openDashboardHovered ? Color.white.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .onHover { openDashboardHovered = $0 }
            Button {
                monitor.selectedSection = .mission
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Power Mission", systemImage: "scope")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 340)
        .foregroundStyle(Color.white)
        .background(Palette.background)
        .preferredColorScheme(.dark)
        .onAppear { monitor.setVisible(true) }
        .onDisappear { monitor.setVisible(false) }
    }

    private var remainingText: String {
        guard let minutes = monitor.battery.minutesRemaining else { return "Time unavailable" }
        return "About \(minutes / 60)h \(minutes % 60)m left"
    }
    private var memoryPercent: Double {
        guard monitor.system.memoryTotal > 0 else { return 0 }
        return 100 * Double(monitor.system.memoryUsed) / Double(monitor.system.memoryTotal)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var monitor: MonitorStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("POWERCLUE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.8).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 14).padding(.top, 20).padding(.bottom, 10)
                ForEach(Section.allCases) { section in
                    Button {
                        monitor.selectedSection = section
                    } label: {
                        Label(section.rawValue, systemImage: section.symbol)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(monitor.selectedSection == section ? Color.white.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Local monitoring · No account")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    .padding(14)
            }
            .padding(.horizontal, 8)
            .frame(width: 180)
            .background(Color.white.opacity(0.025))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(monitor.selectedSection.rawValue)
                            .font(.system(size: 23, weight: .semibold))
                        Spacer()
                        Text(monitor.system.lowPowerMode ? "Low Power Mode · adaptive sampling" : "Live · adaptive sampling")
                            .font(.caption).foregroundStyle(Palette.secondary)
                        Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.bottom, 4)
                    sectionContent
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Palette.background)
        .frame(minWidth: 1120, minHeight: 560)
        .onAppear { monitor.setVisible(true) }
        .onDisappear { monitor.setVisible(false) }
        .sheet(item: Binding(
            get: { monitor.selectedProcessDetail },
            set: { monitor.selectedProcess = $0?.pid }
        )) { process in
            ProcessDetailView(process: process)
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch monitor.selectedSection {
        case .overview: OverviewView()
        case .processes: ProcessesView()
        case .battery: BatteryView()
        case .mission: PowerMissionView()
        case .performance: PerformanceView()
        case .sleep: SleepView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var monitor: MonitorStore

    var body: some View {
        VStack(spacing: 16) {
            Panel {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.title2).foregroundStyle(Palette.red)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(headline).font(.headline)
                        Text(monitor.diagnosis).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                }
            }
            .background(Palette.red.opacity(0.04))
            Button { monitor.selectedSection = .mission } label: {
                HStack(spacing: 12) {
                    Image(systemName: "scope").font(.title2).foregroundStyle(Palette.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Power Mission").font(.headline)
                        Text("Set a battery-life goal and test what actually helps on your Mac.")
                            .font(.caption).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Palette.secondary)
                }
                .padding(17)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border))
            }
            .buttonStyle(.plain)
            HStack(alignment: .top, spacing: 16) {
                BatterySummary()
                PerformanceSummary()
            }
            HStack(alignment: .top, spacing: 16) {
                BatterySignalsCard()
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PERFORMANCE & SYSTEM").font(.caption.bold()).foregroundStyle(Palette.secondary)
                        Text("Thermal: \(monitor.system.thermalState)").font(.title3.bold())
                        Text("Load average: \(monitor.system.loadAverage.formatted(.number.precision(.fractionLength(2))))")
                        Text("Memory pressure: \(monitor.system.memoryPressure)")
                        Text("Disk ↓ \(formatRate(monitor.system.diskReadPerSecond))  ↑ \(formatRate(monitor.system.diskWritePerSecond))")
                        Text("Network ↓ \(formatRate(monitor.system.networkInPerSecond))  ↑ \(formatRate(monitor.system.networkOutPerSecond))")
                        if let topCPU = monitor.processes.max(by: { $0.cpuPercent < $1.cpuPercent }) {
                            Text("Top CPU: \(topCPU.name) · \(formatCPUPercent(topCPU.cpuPercent))")
                        }
                        Text("Memory is useful for spotting slowdowns, but RAM size alone does not identify battery drain.")
                            .font(.caption).foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
    }

    private var headline: String {
        if monitor.system.thermalState == "Serious" || monitor.system.thermalState == "Critical" { return "Performance may be reduced" }
        if monitor.topProcess?.impact ?? 0 >= 40 { return "High process activity" }
        return "Mac activity at a glance"
    }
}

private struct BatterySignalsCard: View {
    @EnvironmentObject private var monitor: MonitorStore

    private var candidates: [ProcessSnapshot] {
        Array(monitor.processes.filter { $0.impact >= 15 }.prefix(3))
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("POSSIBLE BATTERY CONTRIBUTORS")
                    .font(.caption.bold()).foregroundStyle(Palette.secondary)
                if candidates.isEmpty {
                    Text("No elevated activity signals right now.")
                        .font(.headline)
                } else {
                    ForEach(candidates) { process in
                        Button { monitor.selectedProcess = process.pid } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(process.name).font(.subheadline.bold()).lineLimit(1)
                                    Text(process.reasons.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(Palette.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 6)
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(process.impactLabel)
                                        .foregroundStyle(impactColor(process.impact))
                                    if process.cpuPowerWatts != nil {
                                        Text(formatCPUWatts(process.cpuPowerWatts))
                                            .foregroundStyle(Palette.secondary)
                                    }
                                }
                                .font(.caption)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(monitor.battery.isOnAC
                     ? "On power adapter. These signals show activity that could use battery if unplugged."
                     : "Ranked from CPU, wakeups, disk and network activity. CPU W estimates CPU power only; it is not total process power or a share of battery drain.")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
        }
    }
}

private struct BatterySummary: View {
    @EnvironmentObject private var monitor: MonitorStore
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 15) {
                Label("BATTERY", systemImage: "battery.75percent")
                    .font(.caption.bold()).foregroundStyle(Palette.secondary)
                Metric("Charge", value: monitor.battery.percent.map { "\($0)%" } ?? "Unavailable",
                       subtitle: monitor.battery.isOnAC ? "Connected to power" : "On battery")
                Text(monitor.battery.isOnAC ? "Charging or powered" : drainStatus)
                    .font(.caption.bold())
                    .foregroundStyle(monitor.battery.isOnAC ? .green : Palette.red)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent drain").font(.caption).foregroundStyle(Palette.secondary)
                        Text(monitor.battery.drainPerHour.map { "−\($0.formatted(.number.precision(.fractionLength(1))))%/h" } ?? "Collecting baseline…")
                            .foregroundStyle(Palette.red)
                    }
                    Spacer()
                    if let minutes = monitor.battery.minutesRemaining {
                        Text("~\(minutes / 60)h \(minutes % 60)m left")
                            .font(.caption).foregroundStyle(Palette.secondary)
                    }
                }
                if let watts = monitor.battery.watts {
                    Text("Battery output: \(String(format: "%.1f W", watts))")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
                HStack(spacing: 12) {
                    drainAverage("1m", monitor.battery.averageDrain1m, monitor.battery.averageWatts1m)
                    drainAverage("5m", monitor.battery.averageDrain5m, monitor.battery.averageWatts5m)
                    drainAverage("15m", monitor.battery.averageDrain15m, monitor.battery.averageWatts15m)
                }
            }
        }
    }
    private var drainStatus: String {
        guard let current = monitor.battery.averageDrain5m,
              let baseline = monitor.drainBaseline, baseline > 0 else { return "Building a personal drain baseline" }
        let ratio = current / baseline
        if ratio >= 2 { return "Very high vs. your baseline" }
        if ratio >= 1.5 { return "High vs. your baseline" }
        if ratio >= 0.8 { return "Normal vs. your baseline" }
        return "Low vs. your baseline"
    }
    private func drainAverage(_ period: String, _ value: Double?, _ watts: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(period).foregroundStyle(Palette.secondary)
            Text(value.map { String(format: "%.1f%%/h", $0) } ?? "—")
                .monospacedDigit()
            Text(watts.map { String(format: "%.1f W", $0) } ?? "—")
                .monospacedDigit().foregroundStyle(Palette.secondary)
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PerformanceSummary: View {
    @EnvironmentObject private var monitor: MonitorStore
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 17) {
                Label("PERFORMANCE", systemImage: "cpu")
                    .font(.caption.bold()).foregroundStyle(Palette.secondary)
                ProgressMetric(title: "CPU", value: monitor.system.cpuPercent, color: .orange)
                ProgressMetric(title: "Memory", value: memoryPercent, color: Palette.blue)
                HStack {
                    Text("Swap").foregroundStyle(Palette.secondary)
                    Spacer()
                    Text(formatBytes(monitor.system.swapUsed))
                }
                .font(.caption)
                HStack {
                    Text("Memory pressure").foregroundStyle(Palette.secondary)
                    Spacer()
                    Text(monitor.system.memoryPressure)
                }.font(.caption)
                HStack {
                    Text("Thermal").foregroundStyle(Palette.secondary)
                    Spacer()
                    Text(monitor.system.thermalState)
                }
                .font(.caption)
                HStack {
                    Text("Low Power Mode").foregroundStyle(Palette.secondary)
                    Spacer()
                    Text(monitor.system.lowPowerMode ? "On" : "Off")
                }.font(.caption)
            }
        }
    }
    private var memoryPercent: Double {
        guard monitor.system.memoryTotal > 0 else { return 0 }
        return 100 * Double(monitor.system.memoryUsed) / Double(monitor.system.memoryTotal)
    }
}

private struct ProcessesView: View {
    @EnvironmentObject private var monitor: MonitorStore
    @State private var sort: Sort = .impact
    @State private var showingGlossary = false
    @State private var groupApplications = false
    @State private var expandedGroups: Set<String> = []

    private enum Sort: String, CaseIterable { case impact = "Activity", cpu = "CPU", cpuPower = "CPU W", memory = "Memory", wakeups = "Wakeups", disk = "Disk", network = "Network" }
    private var sorted: [ProcessSnapshot] {
        monitor.filteredProcesses.sorted {
            switch sort {
            case .impact: $0.impact > $1.impact
            case .cpu: $0.cpuPercent > $1.cpuPercent
            case .cpuPower: ($0.cpuPowerWatts ?? -1) > ($1.cpuPowerWatts ?? -1)
            case .memory: $0.memoryBytes > $1.memoryBytes
            case .wakeups: ($0.wakeupsPerSecond ?? 0) > ($1.wakeupsPerSecond ?? 0)
            case .disk: (($0.diskReadPerSecond ?? 0) + ($0.diskWritePerSecond ?? 0)) > (($1.diskReadPerSecond ?? 0) + ($1.diskWritePerSecond ?? 0))
            case .network: (($0.networkInPerSecond ?? 0) + ($0.networkOutPerSecond ?? 0)) > (($1.networkInPerSecond ?? 0) + ($1.networkOutPerSecond ?? 0))
            }
        }
    }
    private var groups: [(name: String, members: [ProcessSnapshot])] {
        Dictionary(grouping: sorted) { $0.applicationName ?? $0.name }
            .map { (name: $0.key, members: $0.value) }
            .sorted { $0.members.reduce(0) { $0 + $1.impact } > $1.members.reduce(0) { $0 + $1.impact } }
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search process or PID", text: $monitor.search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 270)
                Toggle("Group by app", isOn: $groupApplications).toggleStyle(.checkbox)
                Spacer()
                Button { showingGlossary.toggle() } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Explain the process metrics")
                .popover(isPresented: $showingGlossary, arrowEdge: .bottom) {
                    ProcessGlossaryView()
                }
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 180)
            }
            Text("Activity ranks possible battery contributors from CPU, wakeups, disk and network. CPU W estimates CPU power only; it excludes GPU, display and other power use.")
                .font(.caption).foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Panel {
                LazyVStack(spacing: 0) {
                    HStack {
                        Text("PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                            .help("A running app or background system task.")
                        Text("PID").frame(width: 55, alignment: .trailing)
                            .help("Process ID: the number macOS assigns to a running process.")
                        Text("CPU").frame(width: 58, alignment: .trailing)
                            .help("Current processor use. 100% means one CPU core is fully busy.")
                        Text("CPU W").frame(width: 78, alignment: .trailing)
                            .help("Estimated average CPU power from macOS per-process CPU energy accounting. Excludes GPU, display, network and other power use. Unavailable on unsupported Macs or processes.")
                        Text("MEMORY").frame(width: 82, alignment: .trailing)
                            .help("The process's physical memory footprint.")
                        Text("WAKEUPS").frame(width: 76, alignment: .trailing)
                            .help("How often the process wakes the CPU, shown per minute.")
                        Text("DISK").frame(width: 72, alignment: .trailing)
                            .help("Read plus write throughput for this process.")
                        Text("NETWORK").frame(width: 72, alignment: .trailing)
                            .help("Incoming plus outgoing traffic. Refreshed about every 10 seconds.")
                        Text("SLEEP").frame(width: 45, alignment: .trailing)
                            .help("Whether this process currently holds a sleep-prevention assertion.")
                        Text("ACTIVITY").frame(width: 110, alignment: .trailing)
                            .help("Possible battery-use signals from CPU, wakeups, disk and network. This is not measured battery power.")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.secondary)
                    .padding(.bottom, 10)
                    if groupApplications {
                        ForEach(groups, id: \.name) { group in
                            Button {
                                if expandedGroups.contains(group.name) { expandedGroups.remove(group.name) }
                                else { expandedGroups.insert(group.name) }
                            } label: {
                                HStack {
                                    Image(systemName: expandedGroups.contains(group.name) ? "chevron.down" : "chevron.right")
                                    Text(group.name).fontWeight(.semibold)
                                    Text("\(group.members.count)").foregroundStyle(Palette.secondary)
                                    Spacer()
                                    Text("CPU \(formatCPUPercent(group.members.reduce(0) { $0 + $1.cpuPercent }))")
                                    Text("· Memory \(formatBytes(group.members.reduce(0) { $0 + $1.memoryBytes }))")
                                    Text("· CPU \(formatCPUWatts(group.members.compactMap(\.cpuPowerWatts).reduce(0, +)))")
                                }
                                .font(.caption).padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if expandedGroups.contains(group.name) {
                                ForEach(group.members) { process in processRow(process, indented: true) }
                            }
                            Divider().opacity(0.3)
                        }
                    } else {
                        ForEach(sorted) { process in
                            processRow(process, indented: false)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
            Text("Some processes restrict resource data. Percentages show one CPU core as 100% for each process.")
                .font(.caption).foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func processRow(_ process: ProcessSnapshot, indented: Bool) -> some View {
        Button { monitor.selectedProcess = process.pid } label: {
            HStack(spacing: 6) {
                Text(process.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, indented ? 15 : 0)
                Text("\(process.pid)").frame(width: 55, alignment: .trailing)
                Text(formatCPUPercent(process.cpuPercent)).frame(width: 58, alignment: .trailing)
                Text(formatCPUWatts(process.cpuPowerWatts)).frame(width: 78, alignment: .trailing)
                Text(formatBytes(process.memoryBytes)).frame(width: 82, alignment: .trailing)
                Text(process.wakeupsPerSecond.map { "\(Int($0 * 60))/m" } ?? "—")
                    .frame(width: 76, alignment: .trailing)
                Text(formatRate((process.diskReadPerSecond ?? 0) + (process.diskWritePerSecond ?? 0)))
                    .frame(width: 72, alignment: .trailing)
                Text(process.networkInPerSecond == nil ? "—" : formatRate((process.networkInPerSecond ?? 0) + (process.networkOutPerSecond ?? 0)))
                    .frame(width: 72, alignment: .trailing)
                Image(systemName: process.preventsSleep ? "moon.zzz.fill" : "minus")
                    .foregroundStyle(process.preventsSleep ? .orange : Palette.secondary)
                    .frame(width: 45, alignment: .trailing)
                Text(process.impactLabel).foregroundStyle(impactColor(process.impact))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: 110, alignment: .trailing)
            }
            .font(.system(size: 12)).monospacedDigit()
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct ProcessGlossaryView: View {
    private let definitions: [(String, String)] = [
        ("Process", "An app or background task currently running on your Mac."),
        ("PID", "Process ID: the unique number macOS assigns while that process runs."),
        ("CPU", "Processor use right now. 100% means one CPU core is fully busy."),
        ("CPU W", "Estimated CPU-only power from macOS energy accounting over the latest sample. Other parts of the app's power use are excluded."),
        ("Memory", "Physical memory footprint used by the process."),
        ("Wakeups", "Times per minute the process wakes the CPU from idle."),
        ("Disk", "Bytes read and written per second by the process."),
        ("Network", "Bytes received and sent per second, sampled about every 10 seconds."),
        ("Sleep", "An active power assertion can delay idle sleep. It does not prove battery drain."),
        ("Activity", "A relative signal from CPU, wakeups, disk and network. It suggests what to inspect for battery use; it is not measured power. Memory alone does not count.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Process metrics").font(.headline)
            ForEach(definitions, id: \.0) { term, explanation in
                HStack(alignment: .top, spacing: 10) {
                    Text(term).fontWeight(.semibold).frame(width: 70, alignment: .leading)
                    Text(explanation).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(Palette.background)
        .foregroundStyle(Color.white)
        .preferredColorScheme(.dark)
    }
}

private struct PowerMissionView: View {
    @EnvironmentObject private var monitor: MonitorStore
    @AppStorage("powerMissionGoalMinutes") private var goalMinutes = 240
    @State private var selectedAction: MissionAction = .lowPowerMode

    private var mission: PowerMissionState { monitor.mission }
    private var canStart: Bool {
        !monitor.battery.isOnAC && monitor.battery.percent != nil && monitor.battery.watts != nil &&
        (selectedAction != .lowPowerMode || !monitor.system.lowPowerMode)
    }

    var body: some View {
        VStack(spacing: 16) {
            Panel {
                VStack(alignment: .leading, spacing: 13) {
                    Label("POWER MISSION", systemImage: "scope")
                        .font(.caption.bold()).foregroundStyle(Palette.secondary)
                    Text("What runtime are you aiming for?")
                        .font(.title2.bold())
                    Stepper(value: $goalMinutes, in: 30...720, step: 15) {
                        Text(formatMissionMinutes(goalMinutes)).font(.title3.bold()).monospacedDigit()
                    }
                    .frame(maxWidth: 250)
                    if monitor.battery.isOnAC {
                        Text("Unplug to compare battery power and run a mission.")
                            .foregroundStyle(Palette.secondary)
                    } else if let remaining = monitor.battery.minutesRemaining {
                        Text(remaining >= goalMinutes
                             ? "macOS estimates about \(formatMissionMinutes(remaining)) remaining — enough for this goal at the current pace."
                             : "macOS estimates about \(formatMissionMinutes(remaining)) remaining — roughly \(formatMissionMinutes(goalMinutes - remaining)) short of your goal.")
                            .foregroundStyle(remaining >= goalMinutes ? .green : .orange)
                    } else {
                        Text("macOS has not provided a time estimate yet. You can still compare power draw.")
                            .foregroundStyle(Palette.secondary)
                    }
                    Text("Time remaining is an estimate and may change as your work changes.")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
                .font(.subheadline)
            }

            Panel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TEST ONE CHANGE").font(.caption.bold()).foregroundStyle(Palette.secondary)
                            Text(stageTitle).font(.title3.bold())
                        }
                        Spacer()
                        if mission.phase != .ready {
                            Button("Reset") { monitor.resetMission() }
                                .buttonStyle(.borderless)
                        }
                    }

                    switch mission.phase {
                    case .ready:
                        Picker("What will you test?", selection: $selectedAction) {
                            ForEach(MissionAction.allCases) { action in
                                Text(action.rawValue).tag(action)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 440, alignment: .leading)
                        Text(selectedAction.instruction).foregroundStyle(Palette.secondary)
                        if selectedAction == .lowPowerMode && monitor.system.lowPowerMode {
                            Text("Low Power Mode is already on. Pick another change to test.")
                                .foregroundStyle(.orange)
                        } else if !monitor.battery.isOnAC && monitor.battery.watts == nil {
                            Text("This Mac has not provided a battery-power reading yet. The test needs that value.")
                                .foregroundStyle(.orange)
                        }
                        Button("Start baseline") { monitor.startMission(selectedAction) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canStart)
                    case .baseline:
                        Text("Keep working as usual. Make your change only after the baseline finishes.")
                            .foregroundStyle(Palette.secondary)
                        stageProgress
                    case .change:
                        Text(mission.action.instruction).foregroundStyle(Palette.secondary)
                        if let message = mission.message {
                            Text(message).foregroundStyle(.orange)
                        }
                        Button("I made the change") { monitor.markMissionChange() }
                            .buttonStyle(.borderedProminent)
                            .disabled(mission.action == .lowPowerMode && !monitor.system.lowPowerMode)
                        if mission.action != .lowPowerMode {
                            Text("PowerClue cannot verify this manual action; it will compare whole-Mac battery power after your marker.")
                                .font(.caption).foregroundStyle(Palette.secondary)
                        }
                    case .after:
                        Text("Continue the same kind of work while PowerClue measures again.")
                            .foregroundStyle(Palette.secondary)
                        stageProgress
                    case .finished:
                        if let result = mission.result { resultView(result) }
                        Button("Run another test") { monitor.resetMission() }
                            .buttonStyle(.bordered)
                    case .interrupted:
                        Text(mission.message ?? "This test was interrupted.")
                            .foregroundStyle(.orange)
                        Button("Start again") { monitor.resetMission() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .font(.subheadline)
            }

            Text("Each stage allows 15 seconds to settle, then samples battery output for 90 seconds. PowerClue compares median watts; a single before/after test cannot prove what caused a change.")
                .font(.caption).foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if monitor.system.lowPowerMode && selectedAction == .lowPowerMode { selectedAction = .pauseApp }
        }
    }

    private var stageTitle: String {
        switch mission.phase {
        case .ready: "Choose a reversible experiment"
        case .baseline: "Measuring before"
        case .change: "Make your change"
        case .after: "Measuring after"
        case .finished: "Your result"
        case .interrupted: "Test interrupted"
        }
    }

    private var stageProgress: some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(value: mission.progress())
                .tint(Palette.blue)
            Text("\(Int(mission.progress() * 100))% · \(mission.phase == .baseline ? mission.baseline.count : mission.after.count) readings")
                .font(.caption).foregroundStyle(Palette.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder private func resultView(_ result: MissionResult) -> some View {
        HStack(spacing: 16) {
            Metric("Before", value: String(format: "%.1f W", result.beforeWatts))
            Image(systemName: "arrow.right").foregroundStyle(Palette.secondary)
            Metric("After", value: String(format: "%.1f W", result.afterWatts))
        }
        Divider()
        switch result.verdict {
        case .lower:
            Text(String(format: "Battery power was %.1f W lower after the change.", result.differenceWatts))
                .font(.headline).foregroundStyle(.green)
            if let minutes = result.approximateMinutesGained {
                Text("At the same workload, that could mean about +\(formatMissionMinutes(minutes)) of runtime.")
                    .font(.subheadline)
            }
            Text("Confidence: moderate. The drop exceeds the variation in these two windows, but repeat the test for a stronger conclusion.")
                .foregroundStyle(Palette.secondary)
        case .higher:
            Text(String(format: "Battery power was %.1f W higher after the change.", -result.differenceWatts))
                .font(.headline).foregroundStyle(.orange)
            Text("This comparison did not show a saving. Repeat under similar work to check it.")
                .foregroundStyle(Palette.secondary)
        case .inconclusive:
            Text("No reliable difference yet")
                .font(.headline).foregroundStyle(.orange)
            Text("The change was smaller than normal reading variation, or CPU activity changed substantially. Try again during steadier work.")
                .foregroundStyle(Palette.secondary)
        }
        Text("Whole-Mac median: \(result.beforeCount) before and \(result.afterCount) after readings. CPU activity: \(Int(result.beforeCPU))% → \(Int(result.afterCPU))%. This is not a per-app watt measurement.")
            .font(.caption).foregroundStyle(Palette.secondary)
    }

    private func formatMissionMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }
}

private struct BatteryView: View {
    @EnvironmentObject private var monitor: MonitorStore
    var body: some View {
        VStack(spacing: 16) {
            BatterySummary()
            BatterySignalsCard()
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("CHARGE · THIS SESSION").font(.caption.bold()).foregroundStyle(Palette.secondary)
                    Chart(monitor.history.compactMap { sample -> HistorySample? in sample.batteryPercent == nil ? nil : sample }) { sample in
                        LineMark(x: .value("Time", sample.date), y: .value("Charge", sample.batteryPercent ?? 0))
                            .foregroundStyle(Palette.red)
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 220)
                }
            }
        }
    }
}

private struct PerformanceView: View {
    @EnvironmentObject private var monitor: MonitorStore
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Panel { Metric("CPU", value: "\(Int(monitor.system.cpuPercent))%", subtitle: "User \(Int(monitor.system.userCPU))% · System \(Int(monitor.system.systemCPU))%", color: Palette.blue) }
                Panel { Metric("Memory", value: formatBytes(monitor.system.memoryUsed), subtitle: "of \(formatBytes(monitor.system.memoryTotal))") }
                Panel { Metric("Swap", value: formatBytes(monitor.system.swapUsed), subtitle: "Thermal: \(monitor.system.thermalState)") }
            }
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("CPU · THIS SESSION").font(.caption.bold()).foregroundStyle(Palette.secondary)
                    Chart(monitor.history) { sample in
                        LineMark(x: .value("Time", sample.date), y: .value("CPU", sample.cpuPercent))
                            .foregroundStyle(Palette.blue)
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 240)
                }
            }
        }
    }
}

private struct ProcessDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var monitor: MonitorStore
    let process: ProcessSnapshot
    private var processHistory: [(date: Date, process: ProcessSnapshot)] {
        monitor.history.compactMap { sample in
            sample.topProcesses.first(where: { $0.pid == process.pid }).map { (sample.date, $0) }
        }
    }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text(process.name).font(.title2.bold())
                    Text("PID \(process.pid) · \(process.impactLabel) activity signals")
                        .font(.caption).foregroundStyle(impactColor(process.impact))
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            HStack {
                Metric("CPU", value: formatCPUPercent(process.cpuPercent))
                Metric("CPU W", value: formatCPUWatts(process.cpuPowerWatts))
                Metric("Memory", value: formatBytes(process.memoryBytes))
                Metric("Wakeups", value: process.wakeupsPerSecond.map { "\(Int($0 * 60))/min" } ?? "Unavailable")
            }
            HStack {
                Metric("CPU time", value: String(format: "%.1f s", process.cpuSeconds))
                Metric("Disk read", value: process.diskReadPerSecond.map(formatRate) ?? "Unavailable")
                Metric("Disk write", value: process.diskWritePerSecond.map(formatRate) ?? "Unavailable")
            }
            HStack {
                Metric("Network in", value: process.networkInPerSecond.map(formatRate) ?? "Unavailable")
                Metric("Network out", value: process.networkOutPerSecond.map(formatRate) ?? "Unavailable")
                Metric("Sleep assertion", value: process.preventsSleep ? "Active" : "None")
            }
            Divider()
            Text("Why might this process use battery?").font(.headline)
            Text("CPU W is estimated from this process's CPU energy over the latest sample. It excludes GPU, network, disk, display and shared system work. Activity \(process.impact)/100 also uses wakeups, disk and network; it is not total watts or a share of battery drain.")
                .font(.caption).foregroundStyle(Palette.secondary)
            ForEach(process.reasons, id: \.self) { reason in
                Label(reason, systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
            Text("High CPU sustained over time is a strong clue. Frequent wakeups can matter even with low CPU. Memory alone is not evidence of battery drain.")
                .font(.caption).foregroundStyle(Palette.secondary)
            Divider()
            Text("Recent CPU activity").font(.headline)
            if processHistory.count > 1 {
                Chart(processHistory, id: \.date) { point in
                    LineMark(x: .value("Time", point.date), y: .value("CPU", point.process.cpuPercent))
                        .foregroundStyle(Palette.blue)
                }.frame(height: 140)
            } else {
                Text("This process has not appeared among the top five in enough saved samples for a chart.")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
        }
        .padding(24)
        .frame(width: 600)
        }
        .frame(height: 560)
        .background(Palette.background)
        .preferredColorScheme(.dark)
    }
}

private enum HistoryMetric: String, CaseIterable, Identifiable {
    case charge = "Charge", batteryPower = "Battery W", drain = "Drain %/h"
    case cpu = "CPU", memory = "Memory", swap = "Swap"
    case download = "Network in", upload = "Network out"
    case diskRead = "Disk read", diskWrite = "Disk write", thermal = "Thermal"

    var id: Self { self }
    func value(_ sample: HistorySample) -> Double? {
        switch self {
        case .charge: sample.batteryPercent.map(Double.init)
        case .batteryPower: sample.batteryWatts
        case .drain: sample.drainPerHour
        case .cpu: sample.cpuPercent
        case .memory: Double(sample.memoryUsed) / 1_073_741_824
        case .swap: Double(sample.swapUsed) / 1_073_741_824
        case .download: sample.networkInPerSecond / 1_048_576
        case .upload: sample.networkOutPerSecond / 1_048_576
        case .diskRead: sample.diskReadPerSecond / 1_048_576
        case .diskWrite: sample.diskWritePerSecond / 1_048_576
        case .thermal:
            switch sample.thermalState { case "Critical": 3; case "Serious": 2; case "Fair": 1; default: 0 }
        }
    }
    var unit: String {
        switch self {
        case .charge, .cpu: "%"
        case .drain: "%/h"
        case .batteryPower: "W"
        case .memory, .swap: "GiB"
        case .download, .upload, .diskRead, .diskWrite: "MiB/s"
        case .thermal: "state"
        }
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var monitor: MonitorStore
    @State private var metric: HistoryMetric = .cpu
    @State private var selectedTime: Date?

    private var chartSamples: [HistorySample] { monitor.history.filter { metric.value($0) != nil } }
    private var selectedSample: HistorySample? {
        guard let selectedTime else { return monitor.history.last }
        return monitor.history.min { abs($0.date.timeIntervalSince(selectedTime)) < abs($1.date.timeIntervalSince(selectedTime)) }
    }

    var body: some View {
        VStack(spacing: 16) {
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("LOCAL HISTORY").font(.caption.bold()).foregroundStyle(Palette.secondary)
                        Spacer()
                        Picker("Range", selection: $monitor.historyRange) {
                            ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).frame(width: 340)
                    }
                    Picker("Metric", selection: $metric) {
                        ForEach(HistoryMetric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu).frame(width: 190)
                    if chartSamples.isEmpty {
                        ContentUnavailableView("No samples yet", systemImage: "chart.xyaxis.line",
                                               description: Text("Keep the monitor running to build a local history."))
                            .frame(height: 230)
                    } else {
                        Chart(chartSamples) { sample in
                            if let value = metric.value(sample) {
                                LineMark(x: .value("Time", sample.date), y: .value(metric.rawValue, value))
                                    .foregroundStyle(Palette.blue)
                                    .interpolationMethod(.linear)
                                if sample.thermalState == "Serious" || sample.thermalState == "Critical" {
                                    PointMark(x: .value("Time", sample.date), y: .value(metric.rawValue, value))
                                        .foregroundStyle(Palette.red)
                                }
                            }
                        }
                        .chartXSelection(value: $selectedTime)
                        .frame(height: 260)
                    }
                    Text("Hover or click the chart to inspect a moment. Red points mark serious thermal pressure.")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("WHAT HAPPENED HERE?").font(.caption.bold()).foregroundStyle(Palette.secondary)
                    if let sample = selectedSample {
                        HStack {
                            Text(sample.date.formatted(date: .abbreviated, time: .standard)).font(.headline)
                            Spacer()
                            if let value = metric.value(sample) {
                                Text(String(format: "%.2f %@", value, metric.unit)).font(.headline).monospacedDigit()
                            }
                        }
                        Text("CPU \(formatCPUPercent(sample.cpuPercent)) · Thermal \(sample.thermalState) · Network ↓ \(formatRate(sample.networkInPerSecond)) ↑ \(formatRate(sample.networkOutPerSecond))")
                            .font(.caption).foregroundStyle(Palette.secondary)
                        if sample.topProcesses.isEmpty {
                            Text("Process details are unavailable for this point.")
                                .font(.caption).foregroundStyle(Palette.secondary)
                        } else {
                            ForEach(sample.topProcesses.prefix(5)) { process in
                                HStack {
                                    Text(process.name).lineLimit(1)
                                    Spacer()
                                    Text(formatCPUPercent(process.cpuPercent)).monospacedDigit()
                                    Text(process.impactLabel).foregroundStyle(impactColor(process.impact)).frame(width: 95, alignment: .trailing)
                                }
                                .font(.caption)
                            }
                        }
                    } else {
                        Text("No history has been recorded yet.").foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
    }
}

private struct SleepView: View {
    @EnvironmentObject private var monitor: MonitorStore
    var body: some View {
        VStack(spacing: 16) {
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SLEEP MONITORING").font(.caption.bold()).foregroundStyle(Palette.secondary)
                    Text("Reports are created after this Mac sleeps and wakes while the monitor is running.")
                    Text("Wake reasons and pre-sleep activity are clues. A process is listed as a possible contributor only; the report cannot prove it caused battery loss.")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
            }
            if monitor.sleepSessions.isEmpty {
                Panel { Text("No sleep sessions recorded yet.").foregroundStyle(Palette.secondary) }
            }
            ForEach(monitor.sleepSessions) { session in
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.start.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                Text(session.end.map { "Woke \($0.formatted(date: .omitted, time: .shortened))" } ?? "Sleep in progress")
                                    .font(.caption).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            Text(duration(session.hours)).font(.title3.bold()).monospacedDigit()
                        }
                        HStack(spacing: 18) {
                            sleepMetric("Battery", value: "\(session.startingBattery.map(String.init) ?? "—")% → \(session.endingBattery.map(String.init) ?? "—")%")
                            sleepMetric("Lost", value: session.batteryLoss.map { "\($0)%" } ?? "—")
                            sleepMetric("Average", value: session.drainPerHour.map { String(format: "%.1f%%/h", $0) } ?? "—")
                        }
                        HStack(spacing: 18) {
                            sleepMetric("DarkWakes", value: "\(session.darkWakes)")
                            sleepMetric("Wakes", value: "\(session.wakeEvents)")
                            sleepMetric("Network wakes", value: "\(session.networkWakes)")
                            sleepMetric("Scheduled", value: "\(session.scheduledWakes)")
                        }
                        Text("Before sleep: \(session.priorBatteryWatts.map { String(format: "%.1f W", $0) } ?? "battery power unavailable") · network ↓ \(formatRate(session.priorNetworkInPerSecond)) ↑ \(formatRate(session.priorNetworkOutPerSecond)) · thermal \(session.priorThermalState)")
                            .font(.caption).foregroundStyle(Palette.secondary)
                        if !session.wakeReasons.isEmpty {
                            Text("Wake reasons: \(session.wakeReasons.prefix(4).joined(separator: ", "))")
                                .font(.caption).foregroundStyle(Palette.secondary)
                        }
                        if !session.priorAssertions.isEmpty {
                            Text("Power assertions before sleep").font(.caption.bold())
                            ForEach(session.priorAssertions.prefix(6)) { assertion in
                                Text("\(assertion.processName) · \(assertion.type)")
                                    .font(.caption).foregroundStyle(Palette.secondary)
                            }
                        }
                        Text(sleepConclusion(session)).font(.caption).foregroundStyle(Palette.secondary)
                    }
                }
            }
            if !monitor.assertions.isEmpty {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CURRENT POWER ASSERTIONS").font(.caption.bold()).foregroundStyle(Palette.secondary)
                        ForEach(monitor.assertions.prefix(12)) { assertion in
                            HStack {
                                Text(assertion.processName).lineLimit(1)
                                Spacer()
                                Text(assertion.type).foregroundStyle(assertion.preventsSleep ? .orange : Palette.secondary)
                            }.font(.caption)
                        }
                    }
                }
            }
        }
    }
    private func sleepMetric(_ name: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption).foregroundStyle(Palette.secondary)
            Text(value).font(.subheadline.bold()).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func duration(_ hours: Double) -> String {
        let minutes = Int(hours * 60)
        return "\(minutes / 60)h \(minutes % 60)m"
    }
    private func sleepConclusion(_ session: SleepSession) -> String {
        guard session.end != nil else { return "Waiting for wake data." }
        if session.darkWakes > 0 || session.networkWakes > 0 {
            let names = Array(Set(session.priorAssertions.map(\.processName))).prefix(3).joined(separator: ", ")
            return "Background wake activity occurred during sleep. \(names.isEmpty ? "" : "\(names) held power assertions before sleep and may be worth checking. ")These observations do not establish the cause of battery drain."
        }
        return "No background wake events were identified in this report. Pre-sleep activity alone cannot establish what caused battery loss."
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var monitor: MonitorStore
    var body: some View {
        VStack(spacing: 16) {
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("MONITORING").font(.caption.bold()).foregroundStyle(Palette.secondary)
                    Text("Sampling: 1 second while a window or menu is open; 5 seconds in the background; 12 seconds in Low Power Mode, except 5 seconds during a Mission measurement.")
                    Text("Network activity and power assertions refresh about every 10 seconds. Sampling pauses during system sleep.")
                    Text("History is stored locally: detailed samples for 48 hours and minute averages for 30 days.")
                    Text("No account, telemetry, administrator access, Accessibility, Screen Recording, or Full Disk Access is required.")
                }.font(.caption)
            }
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DIAGNOSTICS").font(.caption.bold()).foregroundStyle(Palette.secondary)
                    Text("Low Power Mode: \(monitor.system.lowPowerMode ? "On" : "Off")")
                    Text("Monitor CPU: \(monitor.processes.first(where: { $0.pid == getpid() }).map { formatCPUPercent($0.cpuPercent) } ?? "Unavailable")")
                    Text(monitor.selfMonitoringWarning ? "Monitor CPU has stayed above 5% for several samples." : "Monitor resource use is within its normal range.")
                        .foregroundStyle(monitor.selfMonitoringWarning ? .orange : Palette.secondary)
                    Text("Unavailable values appear as —. Some system processes restrict metrics.")
                        .foregroundStyle(Palette.secondary)
                }.font(.caption)
            }
        }
    }
}

private func impactColor(_ impact: Int) -> Color {
    if impact >= 70 { return Palette.red }
    if impact >= 40 { return .orange }
    if impact >= 15 { return .yellow }
    return .green
}
