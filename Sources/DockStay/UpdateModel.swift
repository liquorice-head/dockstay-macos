import Combine
import DockStayCore
import Sparkle

@MainActor
final class UpdateModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    let isConfigured: Bool
    private var controller: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        isConfigured = UpdateConfiguration(
            feedURL: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        ) != nil
        // Only app bundles with a valid feed and verification key can start Sparkle.
        guard isConfigured else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }
}
