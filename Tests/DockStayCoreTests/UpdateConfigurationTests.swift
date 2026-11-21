import Foundation
import Testing
@testable import DockStayCore

struct UpdateConfigurationTests {
    private let key = Data(repeating: 42, count: 32).base64EncodedString()

    @Test func acceptsPublicHTTPSFeed() {
        let url = "https://example.github.io/dockstay/appcast.xml"
        let configuration = UpdateConfiguration(feedURL: url, publicKey: key)
        #expect(configuration?.feedURL.absoluteString == url)
        #expect(configuration?.publicKey == key)
    }

    @Test func missingReleaseConfigurationStaysDisabled() {
        #expect(UpdateConfiguration(feedURL: nil, publicKey: nil) == nil)
        #expect(UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: nil) == nil)
        #expect(UpdateConfiguration(feedURL: nil, publicKey: key) == nil)
    }

    @Test(arguments: ["", "http://example.com/appcast.xml", "file:///tmp/appcast.xml",
                      "https:///", "https://user:token@example.com/feed", "https://example.com/feed#fragment"])
    func rejectsUnsafeFeed(_ url: String) {
        #expect(UpdateConfiguration(feedURL: url, publicKey: key) == nil)
    }

    @Test(arguments: ["", "not a key", Data(repeating: 42, count: 31).base64EncodedString(),
                      Data(repeating: 42, count: 33).base64EncodedString()])
    func rejectsInvalidSigningKey(_ publicKey: String) {
        #expect(UpdateConfiguration(feedURL: "https://example.com/feed", publicKey: publicKey) == nil)
    }
}
