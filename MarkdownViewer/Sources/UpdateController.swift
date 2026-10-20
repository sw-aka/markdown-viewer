import AppKit
import Sparkle
import SwiftUI

@Observable
final class UpdateController: NSObject {
    static let shared = UpdateController()

    enum Phase: Equatable {
        case idle, checking, available, upToDate, downloading, extracting, readyToInstall, installing, failed
    }
    var phase: Phase = .idle
    var release: UpdateRelease?
    var message = ""
    var downloaded: UInt64 = 0
    var expected: UInt64 = 0
    var extractionProgress = 0.0
    var lastChecked: Date?
    var automaticChecks: Bool {
        didSet { UserDefaults.standard.set(automaticChecks, forKey: "checkForUpdatesOnLaunch") }
    }
    var channel: UpdateChannel {
        didSet {
            UserDefaults.standard.set(channel.rawValue, forKey: "updateChannel")
            guard !isBusy, !hasPendingDownload else { return }
            checkTask?.cancel()
            release = nil
            phase = .idle
            if channel != oldValue { check() }
        }
    }
    var progress: Double? {
        if phase == .extracting { return extractionProgress }
        guard phase == .downloading, expected > 0 else { return nil }
        return min(1, Double(downloaded) / Double(expected))
    }
    var isBusy: Bool { [.checking, .downloading, .extracting, .installing].contains(phase) }
    var hasPendingDownload: Bool { [.downloading, .extracting, .readyToInstall, .installing].contains(phase) }
    var showsToolbarStatus: Bool { hasUpdate || hasPendingDownload || (phase == .failed && release != nil) }
    var isInstalling: Bool { phase == .installing }
    var hasUpdate: Bool { release != nil && phase == .available }
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    var repository: String { Bundle.main.object(forInfoDictionaryKey: "MDVUpdateRepository") as? String ?? "sw-aka/markdown-viewer" }
    var buildChannel: String { Bundle.main.object(forInfoDictionaryKey: "MDVBuildChannel") as? String ?? "stable" }

    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var driver: UpdateUserDriver?
    @ObservationIgnored private var didLaunch = false

    override private init() {
        let defaults = UserDefaults.standard
        automaticChecks = defaults.object(forKey: "checkForUpdatesOnLaunch") as? Bool ?? true
        let initialChannel = defaults.string(forKey: "updateChannel")
            ?? (Bundle.main.object(forInfoDictionaryKey: "MDVBuildChannel") as? String ?? "stable")
        channel = UpdateChannel(rawValue: initialChannel) ?? .stable
        super.init()
        // A Development installation may later receive a Stable build. Keep
        // its selected channel rather than replacing it with the new default.
        if defaults.string(forKey: "updateChannel") == nil {
            defaults.set(channel.rawValue, forKey: "updateChannel")
        }
    }

    func launch() {
        guard !didLaunch else { return }
        didLaunch = true
        if automaticChecks { check() }
    }

    func checkFromMenu() {
        guard !hasUpdate, !hasPendingDownload else { return }
        check()
    }

    private var testBase: URL? {
        #if DEBUG
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--update-test-server"), args.indices.contains(index + 1),
           let url = URL(string: args[index + 1]), url.scheme == "http", url.host == "127.0.0.1" { return url }
        #endif
        return nil
    }

    func check() {
        guard !isBusy, !hasPendingDownload else { return }
        phase = .checking
        release = nil
        message = "Checking for updates…"
        let selectedChannel = channel
        let repository = repository
        let base = testBase ?? URL(string: "https://api.github.com")!
        let assetBase = testBase
        checkTask = Task { [weak self] in
            do {
                guard repository.split(separator: "/").count == 2,
                      repository.allSatisfy({ $0.isLetter || $0.isNumber || "-._/".contains($0) }) else {
                    throw UpdateError.configuration("The update repository is not configured.")
                }
                var releases: [GitHubRelease] = []
                // Stable uses GitHub's stable-only endpoint; Development also
                // considers the latest Stable release when newer than previews.
                let endpoints = selectedChannel == .stable
                    ? ["repos/\(repository)/releases/latest"]
                    : ["repos/\(repository)/releases?per_page=100", "repos/\(repository)/releases/latest"]
                for endpoint in endpoints {
                    try Task.checkCancellation()
                    let url = URL(string: endpoint, relativeTo: base.appending(path: "/"))!.absoluteURL
                    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
                    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                    request.setValue("MarkdownViewer/\(self?.currentVersion ?? "0")", forHTTPHeaderField: "User-Agent")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse else { throw UpdateError.network }
                    if http.statusCode == 404 && endpoint.hasSuffix("/latest") { continue }
                    guard http.statusCode == 200 else {
                        throw UpdateError.configuration(http.statusCode == 403 || http.statusCode == 429
                            ? "GitHub is limiting update checks. Please try again later."
                            : "GitHub releases are not available (HTTP \(http.statusCode)).")
                    }
                    if endpoint.hasSuffix("/latest") { releases.append(try JSONDecoder().decode(GitHubRelease.self, from: data)) }
                    else { releases += try JSONDecoder().decode([GitHubRelease].self, from: data) }
                }
                try Task.checkCancellation()
                guard let self else { return }
                let current = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.1.0")
                    ?? AppVersion(currentVersion)!
                let candidate = releases.compactMap { $0.candidate(repository: repository, channel: selectedChannel, assetBase: assetBase) }
                    .filter { AppVersion($0.version)! > current }
                    .max { AppVersion($0.version)! < AppVersion($1.version)! }
                lastChecked = Date()
                release = candidate
                phase = candidate == nil ? .upToDate : .available
                message = candidate == nil ? "No updates available." : "Update available"
            } catch is CancellationError {
                // Changing channel invalidates the previous result.
            } catch {
                guard let self, !Task.isCancelled else { return }
                fail(error.localizedDescription)
            }
        }
    }

    func download() {
        guard phase == .available, release != nil else { return }
        guard let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: publicKey)?.count == 32 else {
            fail("This build has no update verification key. Install a signed release build to enable automatic installation.")
            return
        }
        let userDriver = UpdateUserDriver(controller: self)
        let sparkle = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: self)
        driver = userDriver
        updater = sparkle
        downloaded = 0
        expected = 0
        phase = .downloading
        message = "Preparing download…"
        do {
            try sparkle.start()
            sparkle.checkForUpdates()
        } catch { fail(error.localizedDescription) }
    }

    func installAndRestart() {
        guard phase == .readyToInstall else { return }
        driver?.confirmInstallation()
    }

    func cancelDownload() {
        guard phase == .downloading else { return }
        driver?.cancel?()
        phase = release == nil ? .idle : .available
        message = "Download cancelled."
    }

    func fail(_ text: String) {
        driver?.cancelPendingInstallation()
        phase = .failed
        message = text
        SessionRecovery.shared.cancelInstallation()
    }
}

extension UpdateController: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? { release?.feedURL.absoluteString }
}

private enum UpdateError: LocalizedError {
    case configuration(String), network
    var errorDescription: String? {
        switch self {
        case .configuration(let message): message
        case .network: "Could not connect to GitHub. Check your connection and try again."
        }
    }
}

final class UpdateUserDriver: NSObject, SPUUserDriver {
    weak var controller: UpdateController?
    var cancel: (() -> Void)?
    private var installationChoice: CheckedContinuation<SPUUserUpdateChoice, Never>?

    func confirmInstallation() {
        let choice = installationChoice
        installationChoice = nil
        choice?.resume(returning: .install)
    }

    func cancelPendingInstallation() {
        let choice = installationChoice
        installationChoice = nil
        choice?.resume(returning: .skip)
    }
    init(controller: UpdateController) { self.controller = controller }

    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { cancel = cancellation }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        guard let release = controller?.release, appcastItem.versionString == release.version,
              !appcastItem.isInformationOnlyUpdate else {
            controller?.fail("The update feed does not match the selected release.")
            return .dismiss
        }
        return .install
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
    func showUpdateNotFoundWithError(_ error: any Error) async { controller?.fail(error.localizedDescription) }
    func showUpdaterError(_ error: any Error) async { controller?.fail(error.localizedDescription) }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancel = cancellation
        controller?.phase = .downloading
        controller?.message = "Downloading update…"
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { controller?.expected = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) { controller?.downloaded += length }
    func showDownloadDidStartExtractingUpdate() {
        cancel = nil
        controller?.phase = .extracting
        controller?.message = "Verifying and preparing update…"
    }
    func showExtractionReceivedProgress(_ progress: Double) { controller?.extractionProgress = min(1, max(0, progress)) }
    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        guard let controller else { return .dismiss }
        // Keep editing available and capture the session only after confirmation.
        let choice = await withCheckedContinuation { continuation in
            installationChoice = continuation
            controller.phase = .readyToInstall
            controller.message = "Ready to install"
        }
        guard choice == .install, controller.phase == .readyToInstall else { return .skip }
        controller.phase = .installing
        controller.message = "Saving your windows and restarting…"
        do {
            try await SessionRecovery.shared.prepareForInstallation()
            return .install
        } catch {
            controller.fail("Your session could not be saved. The update was stopped: \(error.localizedDescription)")
            return .skip
        }
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {}
    func dismissUpdateInstallation() { cancelPendingInstallation() }
}
