//
//  AppState+HidingCheck.swift
//  Ice
//

import Cocoa
import Combine
import IceCore
import MenuBarDetectorFeed

extension AppState {
    /// Builds the macOS 27 hiding check (plan D7, 4.4) from Ice's state:
    /// only publishers and closures reach the verifier, never a manager.
    @available(macOS 27, *)
    func makeHidingVerifier() -> HidingVerifier {
        let hiddenShown = dividerShownPublisher(for: .hidden)
        let alwaysHiddenShown = dividerShownPublisher(for: .alwaysHidden)
        let alwaysHiddenEnabled = settings.advanced.$enableAlwaysHiddenSection.eraseToAnyPublisher()
        let iceBarMode = settings.general.$useIceBar.eraseToAnyPublisher()
        let barHiddenBySystem = menuBarManager.$isMenuBarHiddenBySystemUserDefaults.eraseToAnyPublisher()

        let inputs = Publishers.CombineLatest(
            Publishers.CombineLatest4(hiddenShown, alwaysHiddenShown, alwaysHiddenEnabled, iceBarMode),
            barHiddenBySystem
        )
        .map { combined, barHiddenBySystem in
            VerificationInputs(
                hiddenShown: combined.0,
                alwaysHiddenShown: combined.1,
                alwaysHiddenEnabled: combined.2,
                iceBarMode: combined.3,
                barHiddenBySystem: barHiddenBySystem
            )
        }
        .eraseToAnyPublisher()

        // Recreated only when the display id changes (D19: screen and
        // geometry are resolved on the main actor before the hop).
        var cached: (displayID: CGDirectDisplayID, verification: HidingVerification)?

        return HidingVerifier(
            inputs: inputs,
            sectionMap: { [weak self] in self?.itemManager.discoveredSectionMap ?? [:] },
            iceIconKey: { [weak self] in self?.itemManager.iceIconKey },
            verification: {
                guard let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
                    return nil
                }
                let displayID = screen.displayID
                if let cached, cached.displayID == displayID {
                    return cached.verification
                }
                let verification = HidingVerification.live(screen: screen, ownIdentifiers: .ice)
                cached = (displayID, verification)
                return verification
            },
            report: { [weak self] status in
                // An unchanged status must not invalidate every view of AppState.
                if self?.hidingCheckStatus != status {
                    self?.hidingCheckStatus = status
                }
            }
        )
    }

    /// Whether the given section's control item is currently collapsed
    /// (`.showSection`), `false` if the section does not exist.
    @available(macOS 27, *)
    private func dividerShownPublisher(for name: MenuBarSection.Name) -> AnyPublisher<Bool, Never> {
        guard let section = menuBarManager.section(withName: name) else {
            return Just(false).eraseToAnyPublisher()
        }
        return section.controlItem.$state
            .map { $0 == .showSection }
            .eraseToAnyPublisher()
    }
}
