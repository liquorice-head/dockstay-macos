import Foundation

public struct UpdateConfiguration: Sendable {
    public let feedURL: URL
    public let publicKey: String

    public init?(feedURL: String?, publicKey: String?) {
        guard let feedURL,
              let components = URLComponents(string: feedURL),
              components.scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.fragment == nil,
              let url = components.url,
              let publicKey,
              Data(base64Encoded: publicKey)?.count == 32 else { return nil }
        self.feedURL = url
        self.publicKey = publicKey
    }
}
