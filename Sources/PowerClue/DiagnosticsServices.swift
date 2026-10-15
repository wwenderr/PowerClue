import Foundation
import IOKit.pwr_mgt

struct NetworkRates {
    var incoming: Double
    var outgoing: Double
}

final class NetworkCollector {
    func sample() -> [Int32: NetworkRates] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-n", "-P", "-d", "-L", "2", "-x", "-J", "bytes_in,bytes_out", "-s", "1"]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()
        do { try task.run() } catch { return [:] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [Int32: NetworkRates] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = csvFields(String(line))
            guard fields.count >= 3 else { continue }
            if fields[0].isEmpty {
                result.removeAll() // The second block contains deltas for the latest one-second sample.
                continue
            }
            guard let dot = fields[0].lastIndex(of: "."),
                  let pid = Int32(fields[0][fields[0].index(after: dot)...]),
                  let incoming = Double(fields[1]), let outgoing = Double(fields[2]) else { continue }
            result[pid] = NetworkRates(incoming: max(0, incoming), outgoing: max(0, outgoing))
        }
        return result
    }

    private func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted && index + 1 < characters.count && characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else { quoted.toggle() }
            } else if character == "," && !quoted {
                fields.append(field)
                field = ""
            } else { field.append(character) }
            index += 1
        }
        fields.append(field)
        return fields
    }
}

final class PowerAssertionCollector {
    func sample() -> [PowerAssertion] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let dictionary = unmanaged?.takeRetainedValue() as NSDictionary? else { return [] }
        var result: [PowerAssertion] = []
        for (key, value) in dictionary {
            guard let pid = (key as? NSNumber)?.int32Value,
                  let assertions = value as? NSArray else { continue }
            for case let assertion as NSDictionary in assertions {
                guard (assertion["AssertLevel"] as? NSNumber)?.intValue != 0,
                      let type = assertion["AssertType"] as? String else { continue }
                result.append(PowerAssertion(pid: pid,
                                             processName: assertion["Process Name"] as? String ?? "PID \(pid)",
                                             type: type,
                                             name: assertion["AssertName"] as? String ?? type))
            }
        }
        return result
    }
}

struct SleepEvents {
    var darkWakes = 0
    var wakeEvents = 0
    var networkWakes = 0
    var scheduledWakes = 0
    var reasons: [String] = []
}

final class SleepLogParser {
    func events(from start: Date, to end: Date) -> SleepEvents {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g", "log"]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()
        do { try task.run() } catch { return SleepEvents() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return SleepEvents() }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        var result = SleepEvents()
        for line in text.split(whereSeparator: \.isNewline) {
            let value = String(line)
            guard value.count >= 25,
                  let date = formatter.date(from: String(value.prefix(25))),
                  date >= start.addingTimeInterval(-120), date <= end.addingTimeInterval(120) else { continue }
            let event = String(value.dropFirst(25)).trimmingCharacters(in: .whitespaces)
            let kind = event.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            guard kind == "DarkWake" || kind == "Wake" || kind == "WakeReason" else { continue }
            if kind == "DarkWake" { result.darkWakes += 1 }
            else if kind == "Wake" { result.wakeEvents += 1 }
            if event.localizedCaseInsensitiveContains("network") {
                result.networkWakes += 1
            }
            if event.localizedCaseInsensitiveContains("scheduled") || event.localizedCaseInsensitiveContains("rtc") {
                result.scheduledWakes += 1
            }
            if let range = event.range(of: "Wake reason:") {
                let reason = event[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !reason.isEmpty && !result.reasons.contains(reason) { result.reasons.append(reason) }
            } else if let range = event.range(of: "due to ") {
                let detail = event[range.upperBound...]
                let reason = detail.components(separatedBy: " Using ").first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !reason.isEmpty && !result.reasons.contains(reason) { result.reasons.append(reason) }
            }
        }
        return result
    }
}
