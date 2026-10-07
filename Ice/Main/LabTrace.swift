//
//  LabTrace.swift
//  Ice
//

import Cocoa
import IceCore
import MenuBarDiscovery

/// Ice's trace mode (plan 2026-10-07-icebar-preference-hiding, S1): with
/// `-IceLabTrace YES` under a lab identity, Ice creates its control items by
/// its own code path in IceBar mode with uncalibrated dividers, writes one
/// JSON line per observation to standard output, and quits. Inert otherwise:
/// `record` returns at once while no trace is running.
@MainActor
enum LabTrace {
    /// Decided once, from the launch arguments only, never a stored default.
    static let launch: LabTraceLaunch = {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        func value(_ name: String) -> String? {
            arguments[name].map { $0 as? String ?? String(describing: $0) }
        }
        return LabTraceRule.launch(
            trace: value(LabTraceRule.traceArgument),
            alwaysHidden: value(LabTraceRule.alwaysHiddenArgument),
            bundleID: Bundle.main.bundleIdentifier
        )
    }()

    /// How long after the control items are created their frames are read:
    /// past the main-queue turns that add, remove and size them.
    private static let settleSeconds = 3.0

    /// AX messaging timeout for the read of Ice's own extras.
    private static let readTimeout = 1.0

    private static var session: Session?

    /// A hook in `ControlItem`'s creation; does nothing unless a trace runs.
    static func record(_ point: LabTracePoint, autosaveName: String, statusItem: NSStatusItem? = nil) {
        session?.emit("point", [
            "point": point.rawValue,
            "item": autosaveName,
            "defaults": defaults(for: autosaveName),
            "statusItem": statusItem.map(describe) ?? NSNull(),
        ])
    }

    /// Runs the trace if this launch asked for one, and quits when done.
    /// `false` for a normal launch, which then goes on as always.
    static func runIfRequested(appState: AppState) -> Bool {
        switch launch {
        case .normal:
            return false
        case .refused(let refusal):
            Session.write(["event": "refused", "reason": String(describing: refusal)], to: .standardError)
            exit(2)
        case .trace(let plan):
            start(plan, appState: appState)
            return true
        }
    }

    /// The bootstrap of S1, exactly: polling stopped, three settings set in
    /// memory, each section's setup -- nothing else (`LabTracePlan.steps`).
    private static func start(_ plan: LabTracePlan, appState: AppState) {
        let session = Session()
        self.session = session
        session.emit("start", header(plan))

        DispatchQueue.main.asyncAfter(deadline: .now() + LabTracePlan.capSeconds) {
            session.emit("cap", ["seconds": LabTracePlan.capSeconds])
            exit(3)
        }

        appState.permissions.stopAllChecks()
        appState.settings.general.useIceBar = plan.useIceBar
        appState.settings.general.showIceIcon = plan.showIceIcon
        appState.settings.advanced.enableAlwaysHiddenSection = plan.alwaysHiddenSection
        let sections = appState.menuBarManager.sections
        for section in sections {
            section.performSetup(with: appState)
        }

        DispatchQueue.main.async {
            for section in sections {
                record(.afterMainQueueTurn, autosaveName: section.controlItem.identifier.rawValue)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + settleSeconds) {
            Task {
                await finish(session, sections: sections)
            }
        }
    }

    private static func finish(_ session: Session, sections: [MenuBarSection]) async {
        for section in sections {
            let controlItem = section.controlItem
            session.emit("window", [
                "item": controlItem.identifier.rawValue,
                "isAddedToMenuBar": controlItem.isAddedToMenuBar,
                "frame": controlItem.frame.map(describe) ?? NSNull(),
                "defaults": defaults(for: controlItem.identifier.rawValue),
            ])
        }
        // Read off the main thread, which must stay free to answer it.
        let own = ProcessInfoRecord(
            pid: getpid(),
            bundleID: Bundle.main.bundleIdentifier,
            localizedName: nil,
            executableName: nil,
            launchTime: nil,
            isSelf: true
        )
        let read = await Task.detached {
            LiveExtrasReader(readsLabels: false).read(own, timeout: readTimeout) { false }
        }.value
        session.emit("ax", [
            "trusted": AXIsProcessTrusted(),
            "extrasError": read.extrasError,
            "childrenError": read.childrenError ?? NSNull(),
            "items": read.records.map { record in
                [
                    "identifier": record.identifier.value ?? NSNull(),
                    "frame": record.frame.value.map { [$0.minX, $0.minY, $0.width, $0.height] } ?? NSNull(),
                    "frameError": record.frame.error,
                ] as [String: Any]
            },
        ])
        session.emit("done", [:])
        NSApp.terminate(nil)
    }

    private static func header(_ plan: LabTracePlan) -> [String: Any] {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let names = ControlItem.Identifier.allCases.map(\.rawValue)
        return [
            "bundleID": bundleID,
            "pid": Int(getpid()),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "alwaysHiddenSection": plan.alwaysHiddenSection,
            "steps": LabTracePlan.steps.map(\.rawValue),
            "stores": [
                "appDefaults": bundleID,
                "menuBarAgent": [
                    "file": "~/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist",
                    "dictionary": "TrailingItemPreferredPositions",
                    "keys": names.map { LabTraceStore.key(bundleID: bundleID, autosaveName: $0) },
                    "readBy": "the runner, before the launch and after the quit",
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    /// The three status-item keys Ice writes for one autosave name, as stored
    /// (`ControlItemDefaults`); `null` when absent.
    private static func defaults(for autosaveName: String) -> [String: Any] {
        let keys = [
            ControlItemDefaults.Key<CGFloat>.preferredPosition.rawValue,
            ControlItemDefaults.Key<Bool>.visible.rawValue,
            ControlItemDefaults.Key<Bool>.visibleCC.rawValue,
        ]
        var result = [String: Any]()
        for key in keys {
            result[key] = UserDefaults.standard.object(forKey: "NSStatusItem \(key) \(autosaveName)") ?? NSNull()
        }
        return result
    }

    private static func describe(_ statusItem: NSStatusItem) -> [String: Any] {
        let autosaveName = statusItem.autosaveName as String
        return [
            "autosaveName": autosaveName,
            "isVisible": statusItem.isVisible,
            "length": Double(statusItem.length),
            "defaultsUnderAutosaveName": defaults(for: autosaveName),
        ]
    }

    private static func describe(_ frame: CGRect) -> [Double] {
        [frame.minX, frame.minY, frame.width, frame.height].map { Double($0) }
    }
}

// MARK: - LabTrace.Session

extension LabTrace {
    /// One trace's output: JSON lines on standard output, each with the
    /// event's name and the seconds since the session began.
    private final class Session {
        private let start = ProcessInfo.processInfo.systemUptime

        func emit(_ event: String, _ fields: [String: Any]) {
            var line = fields
            line["event"] = event
            line["t"] = ProcessInfo.processInfo.systemUptime - start
            Self.write(line, to: .standardOutput)
        }

        static func write(_ object: [String: Any], to handle: FileHandle) {
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
                ?? Data(#"{"event":"unencodable"}"#.utf8)
            handle.write(data + Data("\n".utf8))
        }
    }
}
