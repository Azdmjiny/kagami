import Foundation
import Sparkle

@MainActor
final class UpdateManager {
    private let controller: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        if !publicKey.isEmpty, !feedURL.isEmpty {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            // Sparkle validates signing at startup even when automatic checks are disabled.
            controller = nil
        }
    }

    var isConfigured: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
