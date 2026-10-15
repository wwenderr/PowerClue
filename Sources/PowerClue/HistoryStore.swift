import Foundation
import SQLite3

final class HistoryStore {
    private var database: OpaquePointer?
    private var lastMinute: Int = -1
    private var lastCleanup = Date.distantPast
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL? = nil) {
        let directory = (url?.deletingLastPathComponent()) ??
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("EasyActivityMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let location = url ?? directory.appendingPathComponent("history.sqlite")
        guard sqlite3_open(location.path, &database) == SQLITE_OK else {
            if database != nil { sqlite3_close(database) }
            database = nil
            return
        }
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA synchronous=NORMAL")
        let columns = "ts REAL PRIMARY KEY, battery INTEGER, watts REAL, drain REAL, cpu REAL, memory INTEGER, swap INTEGER, net_in REAL, net_out REAL, disk_read REAL, disk_write REAL, thermal TEXT, top_json TEXT"
        execute("CREATE TABLE IF NOT EXISTS samples (\(columns))")
        execute("CREATE TABLE IF NOT EXISTS minute_samples (\(columns))")
        execute("CREATE TABLE IF NOT EXISTS sleep_sessions (id TEXT PRIMARY KEY, start REAL, json TEXT NOT NULL)")
        execute("CREATE INDEX IF NOT EXISTS sleep_start_idx ON sleep_sessions(start DESC)")
        // A previous run may have stopped before its last minute was rolled up.
        let currentMinute = Int(Date().timeIntervalSince1970 / 60) * 60
        execute("INSERT OR REPLACE INTO minute_samples SELECT CAST(ts / 60 AS INTEGER) * 60, AVG(battery), AVG(watts), AVG(drain), AVG(cpu), AVG(memory), AVG(swap), AVG(net_in), AVG(net_out), AVG(disk_read), AVG(disk_write), thermal, top_json FROM samples WHERE ts < \(currentMinute) GROUP BY CAST(ts / 60 AS INTEGER)")
    }

    deinit { if let database { sqlite3_close(database) } }

    func append(_ sample: HistorySample) {
        guard let database else { return }
        let sql = "INSERT OR REPLACE INTO samples VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, sample.date.timeIntervalSince1970)
        if let battery = sample.batteryPercent { sqlite3_bind_int(statement, 2, Int32(battery)) }
        if let watts = sample.batteryWatts { sqlite3_bind_double(statement, 3, watts) }
        if let drain = sample.drainPerHour { sqlite3_bind_double(statement, 4, drain) }
        sqlite3_bind_double(statement, 5, sample.cpuPercent)
        sqlite3_bind_int64(statement, 6, Int64(clamping: sample.memoryUsed))
        sqlite3_bind_int64(statement, 7, Int64(clamping: sample.swapUsed))
        sqlite3_bind_double(statement, 8, sample.networkInPerSecond)
        sqlite3_bind_double(statement, 9, sample.networkOutPerSecond)
        sqlite3_bind_double(statement, 10, sample.diskReadPerSecond)
        sqlite3_bind_double(statement, 11, sample.diskWritePerSecond)
        sqlite3_bind_text(statement, 12, sample.thermalState, -1, transient)
        let top = (try? String(data: JSONEncoder().encode(sample.topProcesses), encoding: .utf8)) ?? "[]"
        sqlite3_bind_text(statement, 13, top, -1, transient)
        sqlite3_step(statement)
        let minute = Int(sample.date.timeIntervalSince1970 / 60)
        if lastMinute >= 0 && minute != lastMinute { rollUp(minute: lastMinute) }
        lastMinute = minute
        if sample.date.timeIntervalSince(lastCleanup) >= 600 {
            cleanup(now: sample.date)
            lastCleanup = sample.date
        }
    }

    func samples(since start: Date, bucketSeconds: Int) -> [HistorySample] {
        guard let database else { return [] }
        let table: String
        if bucketSeconds >= 60 {
            table = "(SELECT * FROM minute_samples UNION ALL SELECT * FROM samples WHERE ts >= (SELECT COALESCE(MAX(ts), 0) + 60 FROM minute_samples))"
        } else {
            table = "samples"
        }
        let sql = "SELECT MAX(ts), AVG(battery), AVG(watts), AVG(drain), AVG(cpu), AVG(memory), AVG(swap), AVG(net_in), AVG(net_out), AVG(disk_read), AVG(disk_write), thermal, top_json FROM \(table) WHERE ts >= ? GROUP BY CAST(ts / \(max(1, bucketSeconds)) AS INTEGER) ORDER BY MAX(ts)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
        var result: [HistorySample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let battery: Int? = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : Int(sqlite3_column_double(statement, 1).rounded())
            let watts: Double? = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 2)
            let drain: Double? = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3)
            let thermal = sqlite3_column_text(statement, 11).map { String(cString: $0) } ?? "Nominal"
            let json = sqlite3_column_text(statement, 12).map { String(cString: $0) } ?? "[]"
            let top = (try? JSONDecoder().decode([ProcessSnapshot].self, from: Data(json.utf8))) ?? []
            result.append(HistorySample(date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                                        batteryPercent: battery, batteryWatts: watts, drainPerHour: drain,
                                        cpuPercent: sqlite3_column_double(statement, 4),
                                        memoryUsed: UInt64(max(0, sqlite3_column_int64(statement, 5))),
                                        swapUsed: UInt64(max(0, sqlite3_column_int64(statement, 6))),
                                        networkInPerSecond: sqlite3_column_double(statement, 7),
                                        networkOutPerSecond: sqlite3_column_double(statement, 8),
                                        diskReadPerSecond: sqlite3_column_double(statement, 9),
                                        diskWritePerSecond: sqlite3_column_double(statement, 10),
                                        thermalState: thermal,
                                        topProcess: top.first?.name, topCPU: top.first?.cpuPercent,
                                        topProcesses: top))
        }
        return result
    }

    func save(_ session: SleepSession) {
        guard let database,
              let data = try? JSONEncoder().encode(session),
              let json = String(data: data, encoding: .utf8) else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO sleep_sessions VALUES (?,?,?)", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, session.id.uuidString, -1, transient)
        sqlite3_bind_double(statement, 2, session.start.timeIntervalSince1970)
        sqlite3_bind_text(statement, 3, json, -1, transient)
        sqlite3_step(statement)
    }

    func sleepSessions() -> [SleepSession] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT json FROM sleep_sessions ORDER BY start DESC LIMIT 100", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [SleepSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0),
                  let session = try? JSONDecoder().decode(SleepSession.self, from: Data(String(cString: text).utf8)) else { continue }
            result.append(session)
        }
        return result
    }

    func drainBaseline() -> Double? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        let since = Date().timeIntervalSince1970 - 30 * 86400
        guard sqlite3_prepare_v2(database,
              "SELECT AVG(drain) FROM minute_samples WHERE ts >= ? AND drain > 0 AND drain < 100",
              -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, since)
        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, 0)
    }

    private func rollUp(minute: Int) {
        let start = minute * 60
        let end = start + 60
        let sql = "INSERT OR REPLACE INTO minute_samples SELECT \(start), AVG(battery), AVG(watts), AVG(drain), AVG(cpu), AVG(memory), AVG(swap), AVG(net_in), AVG(net_out), AVG(disk_read), AVG(disk_write), thermal, top_json FROM samples WHERE ts >= \(start) AND ts < \(end) HAVING COUNT(*) > 0"
        execute(sql)
    }

    private func cleanup(now: Date) {
        execute("DELETE FROM samples WHERE ts < \(now.timeIntervalSince1970 - 48 * 3600)")
        execute("DELETE FROM minute_samples WHERE ts < \(now.timeIntervalSince1970 - 30 * 86400)")
    }

    private func execute(_ sql: String) {
        guard let database else { return }
        sqlite3_exec(database, sql, nil, nil, nil)
    }
}
