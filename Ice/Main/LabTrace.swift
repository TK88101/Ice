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
    /// Before `autosaveName` is assigned, the status item carries AppKit's
    /// own name for it.
    static func record(_ point: LabTracePoint, autosaveName: String, statusItem: NSStatusItem? = nil) {
        session?.emit("point", [
            "point": point.rawValue,
            "item": autosaveName,
            "defaults": defaults(for: autosaveName),
            "statusItemAutosaveName": statusItem.map { $0.autosaveName as String } ?? NSNull(),
            "statusItemIsVisible": statusItem.map(\.isVisible) ?? NSNull(),
            "statusItemLength": statusItem.map { Double($0.length) } ?? NSNull(),
        ])
    }

    /// A refused trace launch quits before any trace step and before Ice's
    /// own setup; `AppState` is already constructed by then (it is
    /// `AppDelegate`'s stored property).
    static func exitIfRefused() {
        guard case .refused(let refusal) = launch else {
            return
        }
        Session.write(["event": "refused", "reason": String(describing: refusal)], to: .standardError)
        exit(2)
    }

    /// The bootstrap of S1, exactly: `LabTracePlan.steps` and nothing else;
    /// then the samples, and the quit.
    static func start(_ plan: LabTracePlan, appState: AppState) {
        let session = Session()
        self.session = session
        session.emit("start", header(plan))

        DispatchQueue.main.asyncAfter(deadline: .now() + LabTracePlan.capSeconds) {
            session.emit("cap", ["seconds": LabTracePlan.capSeconds])
            exit(3)
        }

        let sections = appState.menuBarManager.sections
        for step in LabTracePlan.steps {
            switch step {
            case .stopPermissionChecks:
                appState.permissions.stopAllChecks()
            case .setSettingsInMemory:
                appState.settings.general.useIceBar = plan.useIceBar
                appState.settings.general.showIceIcon = plan.showIceIcon
                appState.settings.advanced.enableAlwaysHiddenSection = plan.alwaysHiddenSection
            case .setUpSections:
                for section in sections {
                    section.performSetup(with: appState)
                }
            }
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
        // Read off the main thread, which must stay free to answer it. Only
        // Ice's own process is read, so its record is built here rather than
        // by enumerating every running app; no start time is needed, since
        // the read is never quarantined.
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

    /// The runner's handshake: the first line a trace writes carries this,
    /// and `run-trace.sh` refuses a build whose binary lacks it. Longer than
    /// 15 bytes, so Swift stores it rather than folding it into the code.
    private static let marker = "IceLabTrace-start-v1"

    /// Also declares what the trace will sample, from the enums themselves,
    /// so `trace-tool.py` checks what arrived against what was promised.
    private static func header(_ plan: LabTracePlan) -> [String: Any] {
        [
            "mode": marker,
            "bundleID": Bundle.main.bundleIdentifier ?? NSNull(),
            "pid": Int(getpid()),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "alwaysHiddenSection": plan.alwaysHiddenSection,
            "steps": LabTracePlan.steps.map(\.rawValue),
            "points": LabTracePoint.allCases.map(\.rawValue),
            "items": ControlItem.Identifier.allCases.map(\.rawValue),
        ]
    }

    /// The three status-item keys Ice writes for one autosave name, read raw
    /// (`ControlItemDefaults`' typed subscript would turn a value of another
    /// type into `nil`); `null` when absent.
    private static func defaults(for autosaveName: String) -> [String: Any] {
        func stored<Value>(_ key: ControlItemDefaults.Key<Value>) -> (String, Any) {
            (key.rawValue, UserDefaults.standard.object(forKey: key.stringKey(for: autosaveName)) ?? NSNull())
        }
        return Dictionary(uniqueKeysWithValues: [
            stored(ControlItemDefaults.Key<CGFloat>.preferredPosition),
            stored(ControlItemDefaults.Key<Bool>.visible),
            stored(ControlItemDefaults.Key<Bool>.visibleCC),
        ])
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
