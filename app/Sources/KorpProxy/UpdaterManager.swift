import Foundation
import Observation
import Sparkle

/// Wraps Sparkle's updater so the SwiftUI menu/settings can trigger update
/// checks and toggle automatic updates. Created once and held by `AppState`.
///
/// The update feed (`SUFeedURL`) and signing key (`SUPublicEDKey`) are declared
/// in `project.yml` → Info.plist. Releases are published to the public
/// `KorpProxy-releases` repo (appcast served via GitHub Pages); see RELEASING.md.
@Observable
final class UpdaterManager {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// Whether a manual update check can be started right now (false while a
    /// check is already in flight). Drives the menu item's enabled state.
    var canCheckForUpdates = false

    init() {
        // startingUpdater: true kicks off Sparkle's scheduled background checks.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        canCheckForUpdates = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates, options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    /// User-facing "automatically check for updates" preference, persisted by
    /// Sparkle itself in UserDefaults.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Current feed URL (for display in Settings).
    var feedURL: String {
        controller.updater.feedURL?.absoluteString
            ?? (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "—")
    }

    /// Presents Sparkle's update UI and checks for updates now.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
