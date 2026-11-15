//  Daily.swift
//  dualband
//
//  The daily Ice: quit, preferences and MenuBarAgent store snapshots, relaunch
//  by path (plan 2026-11-15-secondary-display, G2, G3, G5).

import AppKit

enum Daily {
    static let bundleID = "io.github.tk88101.Ice"
    static let appPath = "/Applications/Ice.app"
    static let storePath = NSHomeDirectory() + "/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar"

    static func running() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
    }

    @discardableResult
    static func shell(_ path: String, _ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// The domain as XML, so two exports can be compared byte for byte.
    static func exportPrefs(to url: URL) -> Bool {
        shell("/usr/bin/defaults", ["export", bundleID, url.path]) == 0
            && shell("/usr/bin/plutil", ["-convert", "xml1", url.path]) == 0
    }

    static func importPrefs(from url: URL) -> Bool {
        shell("/usr/bin/defaults", ["import", bundleID, url.path]) == 0
    }

    /// The store's keys and values, read until two reads a second apart agree (run-s5.sh's settled_store).
    static func settledStore() -> [String: String]? {
        var previous = readStore()
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 1)
            let next = readStore()
            if next == previous { return next }
            previous = next
        }
        return previous
    }

    static func readStore() -> [String: String]? {
        guard let dict = NSDictionary(contentsOfFile: storePath + ".plist") as? [String: Any] else { return nil }
        return dict.mapValues { String(describing: $0) }
    }

    /// Owner keys added or removed is a stop (G2); value changes are reported.
    static func storeDiff(_ before: [String: String], _ after: [String: String]) -> (keysChanged: [String], valuesChanged: [String]) {
        let keys = Set(before.keys).symmetricDifference(after.keys).sorted()
        let values = Set(before.keys).intersection(after.keys).filter { before[$0] != after[$0] }.sorted()
        return (keys, values)
    }

    /// Quits the daily Ice politely; never forced (G3).
    static func quit(timeout: TimeInterval = 15) -> Bool {
        for app in running() { app.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if running().isEmpty { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return running().isEmpty
    }

    /// Relaunches `/Applications/Ice.app` by path and checks the process is that image (G3, G5).
    static func relaunch(timeout: TimeInterval = 20) -> pid_t? {
        shell("/usr/bin/open", [appPath])
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let app = running().first, app.bundleURL?.path == appPath { return app.processIdentifier }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }
}
