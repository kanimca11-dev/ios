import XCTest
@testable import AppifyWebiOS

final class NavigationPolicyTests: XCTestCase {
    let policy = NavigationPolicy("https://cottkart.com/?app_webview=1")
    func testExactHTTPSOrigin() {
        XCTAssertTrue(policy.isInternal(URL(string: "https://cottkart.com:443/shop")!))
        for value in ["http://cottkart.com/", "https://cottkart.com.evil.test/", "https://evil.test/", "https://cottkart.com:444/", "https://user@cottkart.com/"] {
            XCTAssertFalse(policy.isInternal(URL(string: value)!))
        }
    }
    func testUnsafeTargetsAndSchemes() {
        for value in ["file:///private/data", "javascript:alert(1)", "http://cottkart.com", "https://user@cottkart.com"] {
            XCTAssertNil(NavigationPolicy(value).base)
        }
        XCTAssertFalse(NavigationPolicy.externalAllowed(URL(string: "javascript:alert(1)")!))
        XCTAssertFalse(NavigationPolicy.externalAllowed(URL(string: "file:///tmp/a")!))
        XCTAssertTrue(NavigationPolicy.externalAllowed(URL(string: "mailto:help@example.com")!))
    }
    func testRelativeLinksAndHashRoutes() {
        XCTAssertEqual(policy.resolve("#/shop")?.absoluteString, "https://cottkart.com/?app_webview=1#/shop")
        XCTAssertTrue(NavigationPolicy.matches("https://cottkart.com/?app_webview=1#/shop/item?x=1", "/shop"))
        XCTAssertFalse(NavigationPolicy.matches("https://cottkart.com/shopping", "/shop"))
        XCTAssertFalse(NavigationPolicy.matches("https://cottkart.com/shop", "/"))
        XCTAssertNil(policy.resolve("//evil.test/path"))
    }
    func testSparseConfigurationUsesSafeDefaults() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{\"targetUrl\":\"https://cottkart.com\",\"features\":{}}".utf8))
        XCTAssertFalse(config.features.enablePushNotifications)
        XCTAssertFalse(config.features.enableBiometrics)
        XCTAssertFalse(config.features.showBottomNav)
        XCTAssertNil(config.startUrl)
    }
    func testDisabledStateSurvivesEncoding() throws {
        let data = Data("{\"targetUrl\":\"https://cottkart.com\",\"isActive\":false,\"isSubscriptionActive\":false}".utf8)
        let original = try JSONDecoder().decode(AppConfig.self, from: data)
        let restored = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(original))
        XCTAssertFalse(restored.isActive)
        XCTAssertFalse(restored.isSubscriptionActive)
    }
}
