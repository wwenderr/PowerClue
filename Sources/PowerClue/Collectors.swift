import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps

final class BatteryCollector {
    private var readings: [(Date, Int)] = []
    private var wattReadings: [(Date, Double)] = []

    func sample() -> BatterySnapshot {
        var result = BatterySnapshot()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [Any] else { return result }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any],
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            result.percent = Int((Double(capacity) / Double(maximum) * 100).rounded())
            result.isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            result.isOnAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                result.minutesRemaining = minutes
            }
            break
        }
        if let percent = result.percent, !result.isOnAC {
            readings.append((result.timestamp, percent))
            readings.removeAll { result.timestamp.timeIntervalSince($0.0) > 3600 }
            result.averageDrain1m = drain(over: 60, current: percent, at: result.timestamp)
            result.averageDrain5m = drain(over: 300, current: percent, at: result.timestamp)
            result.averageDrain15m = drain(over: 900, current: percent, at: result.timestamp)
            result.drainPerHour = result.averageDrain5m ?? result.averageDrain1m
            result.watts = batteryDischargeWatts()
            if let watts = result.watts {
                wattReadings.append((result.timestamp, watts))
                wattReadings.removeAll { result.timestamp.timeIntervalSince($0.0) > 3600 }
                result.averageWatts1m = averageWatts(over: 60, at: result.timestamp)
                result.averageWatts5m = averageWatts(over: 300, at: result.timestamp)
                result.averageWatts15m = averageWatts(over: 900, at: result.timestamp)
            }
        } else {
            readings.removeAll()
            wattReadings.removeAll()
        }
        return result
    }

    private func averageWatts(over seconds: TimeInterval, at date: Date) -> Double? {
        let values = wattReadings.filter { date.timeIntervalSince($0.0) <= seconds }
        guard let first = values.first, date.timeIntervalSince(first.0) >= seconds * 0.8 else { return nil }
        return values.reduce(0) { $0 + $1.1 } / Double(values.count)
    }

    private func drain(over seconds: TimeInterval, current: Int, at date: Date) -> Double? {
        guard let first = readings.first(where: { date.timeIntervalSince($0.0) <= seconds }),
              date.timeIntervalSince(first.0) >= seconds * 0.8 else { return nil }
        return max(0, Double(first.1 - current) * 3600 / date.timeIntervalSince(first.0))
    }

    private func batteryDischargeWatts() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let current = IORegistryEntryCreateCFProperty(service, "InstantAmperage" as CFString,
                                                             kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber,
              let voltage = IORegistryEntryCreateCFProperty(service, "Voltage" as CFString,
                                                             kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else { return nil }
        let watts = abs(Double(current.int64Value) * Double(voltage.int64Value)) / 1_000_000
        return watts > 0 && watts < 200 ? watts : nil
    }
}

final class SystemCollector {
    private var previousTicks: [UInt32]?

    func sample() -> SystemSnapshot {
        var result = SystemSnapshot()
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) > 0 { result.loadAverage = load[0] }
        result.memoryTotal = ProcessInfo.processInfo.physicalMemory
        result.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        result.thermalState = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }

        var cpu = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if cpuStatus == KERN_SUCCESS {
            let ticks = [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3]
            if let previousTicks {
                let differences = zip(ticks, previousTicks).map { Double($0 &- $1) }
                let total = differences.reduce(0, +)
                if total > 0 {
                    result.userCPU = 100 * differences[Int(CPU_STATE_USER)] / total
                    result.systemCPU = 100 * differences[Int(CPU_STATE_SYSTEM)] / total
                    result.cpuPercent = 100 * (total - differences[Int(CPU_STATE_IDLE)]) / total
                }
            }
            previousTicks = ticks
        }

        var vm = vm_statistics64()
        count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmStatus = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if vmStatus == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let usedPages = UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            result.memoryUsed = min(result.memoryTotal, usedPages * pageSize)
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { result.swapUsed = swap.xsu_used }
        return result
    }
}

final class ProcessCollector {
    private struct Usage {
        var userTime: UInt64
        var systemTime: UInt64
        var start: UInt64
        var wakeups: UInt64
        var read: UInt64
        var write: UInt64
        var memory: UInt64
        var cpuEnergyNanojoules: UInt64?
    }

    private struct Counters {
        var time: Date
        var start: UInt64
        var cpu: UInt64
        var wakeups: UInt64
        var read: UInt64
        var write: UInt64
        var cpuEnergyNanojoules: UInt64?
    }
    private var previous: [Int32: Counters] = [:]
    private var identityCache: [Int32: (start: UInt64, name: String, application: String?, parent: Int32?)] = [:]
    private let nanosecondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return 1 }
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    func sample() -> [ProcessSnapshot] {
        let capacity = max(1024, Int(proc_listallpids(nil, 0)) * 2)
        var pids = [Int32](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        let now = Date()
        var next: [Int32: Counters] = [:]
        var nextIdentity: [Int32: (start: UInt64, name: String, application: String?, parent: Int32?)] = [:]
        var processes: [ProcessSnapshot] = []
        for pid in pids.prefix(Int(count)) where pid > 0 {
            guard let usage = readUsage(pid) else { continue }
            let identity: (start: UInt64, name: String, application: String?, parent: Int32?)
            if let cached = identityCache[pid], cached.start == usage.start {
                identity = cached
            } else {
                var nameBytes = [CChar](repeating: 0, count: 256)
                let nameCount = nameBytes.withUnsafeMutableBytes { proc_name(pid, $0.baseAddress, UInt32($0.count)) }
                guard nameCount > 0 else { continue }
                var bsd = proc_bsdinfo()
                let bsdSize = withUnsafeMutablePointer(to: &bsd) { pointer in
                    proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, Int32(MemoryLayout<proc_bsdinfo>.size))
                }
                identity = (usage.start, String(cString: nameBytes), applicationName(for: pid),
                            bsdSize > 0 ? Int32(bsd.pbi_ppid) : nil)
            }
            nextIdentity[pid] = identity
            let cpu = usage.userTime &+ usage.systemTime
            let wakeups = usage.wakeups
            let counters = Counters(time: now, start: usage.start,
                                    cpu: cpu, wakeups: wakeups,
                                    read: usage.read, write: usage.write,
                                    cpuEnergyNanojoules: usage.cpuEnergyNanojoules)
            next[pid] = counters
            var process = ProcessSnapshot(pid: pid, name: identity.name,
                                          applicationName: identity.application,
                                          parentPID: identity.parent,
                                          cpuSeconds: Double(cpu) * nanosecondsPerTick / 1_000_000_000,
                                          memoryBytes: usage.memory)
            if let prior = previous[pid], prior.start == counters.start {
                let seconds = now.timeIntervalSince(prior.time)
                if seconds > 0, cpu >= prior.cpu {
                    let cpuNanoseconds = Double(cpu - prior.cpu) * nanosecondsPerTick
                    process.cpuPercent = min(999, cpuNanoseconds / (seconds * 10_000_000))
                    process.wakeupsPerSecond = Double(wakeups &- prior.wakeups) / seconds
                    process.diskReadPerSecond = Double(counters.read &- prior.read) / seconds
                    process.diskWritePerSecond = Double(counters.write &- prior.write) / seconds
                    if let currentEnergy = counters.cpuEnergyNanojoules,
                       let previousEnergy = prior.cpuEnergyNanojoules,
                       currentEnergy >= previousEnergy {
                        process.cpuPowerWatts = Double(currentEnergy - previousEnergy) / (seconds * 1_000_000_000)
                    }
                }
            }
            process.cpuSignal = min(60, process.cpuPercent * 1.4)
            process.wakeupSignal = min(20, (process.wakeupsPerSecond ?? 0) * 2)
            process.diskSignal = min(10, ((process.diskReadPerSecond ?? 0) + (process.diskWritePerSecond ?? 0)) / 2_000_000)
            process.impact = Int(min(100, process.cpuSignal + process.wakeupSignal + process.diskSignal))
            processes.append(process)
        }
        previous = next
        identityCache = nextIdentity
        return processes.sorted { $0.impact == $1.impact ? $0.cpuPercent > $1.cpuPercent : $0.impact > $1.impact }
    }

    private func readUsage(_ pid: Int32) -> Usage? {
        #if arch(arm64)
        var v6 = rusage_info_v6()
        let v6Status = withUnsafeMutablePointer(to: &v6) { pointer in
            proc_pid_rusage(pid, RUSAGE_INFO_V6,
                            UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self))
        }
        if v6Status == 0 {
            return Usage(userTime: v6.ri_user_time, systemTime: v6.ri_system_time,
                         start: v6.ri_proc_start_abstime,
                         wakeups: v6.ri_pkg_idle_wkups &+ v6.ri_interrupt_wkups,
                         read: v6.ri_diskio_bytesread, write: v6.ri_diskio_byteswritten,
                         memory: v6.ri_phys_footprint,
                         cpuEnergyNanojoules: v6.ri_energy_nj > 0 ? v6.ri_energy_nj : nil)
        }
        #endif
        var v2 = rusage_info_v2()
        let v2Status = withUnsafeMutablePointer(to: &v2) { pointer in
            proc_pid_rusage(pid, RUSAGE_INFO_V2,
                            UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self))
        }
        guard v2Status == 0 else { return nil }
        return Usage(userTime: v2.ri_user_time, systemTime: v2.ri_system_time,
                     start: v2.ri_proc_start_abstime,
                     wakeups: v2.ri_pkg_idle_wkups &+ v2.ri_interrupt_wkups,
                     read: v2.ri_diskio_bytesread, write: v2.ri_diskio_byteswritten,
                     memory: v2.ri_phys_footprint, cpuEnergyNanojoules: nil)
    }

    private func applicationName(for pid: Int32) -> String? {
        var path = [CChar](repeating: 0, count: 4096)
        guard path.withUnsafeMutableBytes({ proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }) > 0 else { return nil }
        let components = String(cString: path).split(separator: "/")
        guard let bundle = components.first(where: { $0.hasSuffix(".app") }) else { return nil }
        return String(bundle.dropLast(4))
    }
}
