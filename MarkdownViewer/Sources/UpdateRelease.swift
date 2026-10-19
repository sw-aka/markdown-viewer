import Foundation

nonisolated enum UpdateChannel: String, CaseIterable, Codable, Identifiable, Sendable {
    case stable, development
    var id: String { rawValue }
    var title: String { self == .stable ? "Stable" : "Development" }
}

/// Numeric bundle versions shared by the release workflow and Sparkle.
nonisolated struct AppVersion: Comparable, Sendable {
    let components: [Int]
    init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let build = Int(parts[2]) else { return nil }
        components = [major, minor, build]
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

nonisolated struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browser_download_url: URL
    }
    let tag_name: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    func candidate(repository: String, channel: UpdateChannel, assetBase: URL? = nil) -> UpdateRelease? {
        guard !draft, channel == .development || !prerelease else { return nil }
        let prefix = prerelease ? "dev-" : "v"
        guard tag_name.hasPrefix(prefix) else { return nil }
        let version = String(tag_name.dropFirst(prefix.count))
        guard AppVersion(version) != nil else { return nil }
        let expectedBase = (assetBase ?? URL(string: "https://github.com")!)
            .appending(path: repository).appending(path: "releases/download").appending(path: tag_name)
        func asset(_ name: String) -> URL? {
            guard let found = assets.first(where: { $0.name == name }),
                  found.browser_download_url == expectedBase.appending(path: name) else { return nil }
            return found.browser_download_url
        }
        let archiveName = "MarkdownViewer-\(version)-\(prerelease ? "development" : "stable").zip"
        guard let feed = asset("appcast.xml"), asset(archiveName) != nil else { return nil }
        return UpdateRelease(version: version, channel: prerelease ? .development : .stable,
                             notes: body ?? "", feedURL: feed)
    }
}

nonisolated struct UpdateRelease: Equatable, Sendable {
    let version: String
    let channel: UpdateChannel
    let notes: String
    let feedURL: URL
}
