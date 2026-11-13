//
//  LanguagePicker.swift
//  Ice
//

import AppKit
import IceCore
import OSLog
import SwiftUI

/// General settings' language option (plan 2026-11-13-zh-hant, D4). It writes
/// the app's own `AppleLanguages`, which macOS reads at launch, so a change
/// offers a relaunch.
struct LanguagePicker: View {
    @State private var language = LanguageStore.current

    var body: some View {
        IcePicker("Language", selection: $language) {
            Text("System").tag(AppLanguage.system)
            Text(verbatim: "English").tag(AppLanguage.english)
            Text(verbatim: "繁體中文").tag(AppLanguage.traditionalChinese)
        }
        .annotation("Ice uses the new language after it relaunches.")
        .onChange(of: language) { _, newValue in
            LanguageStore.current = newValue
        }
        if language != LanguageStore.atLaunch {
            Button("Relaunch Ice") {
                LanguageStore.relaunch()
            }
        }
    }
}

/// The app's own `AppleLanguages`, read from its persistent domain only: the
/// global list must not read as a choice the owner made.
@MainActor
enum LanguageStore {
    private static let key = "AppleLanguages"

    /// The language this process was started with: read once, before any
    /// write, so a pending change stays pending however often the pane is built.
    /// A command-line `-AppleLanguages` (the lab's) wins, as it does for the bundle.
    static let atLaunch: AppLanguage = {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        if let languages = arguments[key] as? [String] {
            return AppLanguage(storedLanguages: languages)
        }
        return read()
    }()

    static var current: AppLanguage {
        get {
            read()
        }
        set {
            _ = atLaunch
            if let languages = newValue.storedLanguages {
                UserDefaults.standard.set(languages, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    private static func read() -> AppLanguage {
        let domain = Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:))
        return AppLanguage(storedLanguages: domain?[key] as? [String])
    }

    /// Starts a new Ice once this one has quit, then quits.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"", "sh", "\(ProcessInfo.processInfo.processIdentifier)", path]
        do {
            try process.run()
        } catch {
            Logger(category: "LanguagePicker").error("Relaunch failed: \(error, privacy: .public)")
            return
        }
        NSApp.terminate(nil)
    }
}
