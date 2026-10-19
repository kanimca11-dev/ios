import Foundation

/// The same HTTPS origin is the only context allowed to use app privileges.
struct NavigationPolicy {
    let base: URL?
    init(_ target: String) {
        let url = URL(string: target)
        base = url.flatMap { Self.validHTTPS($0) ? $0 : nil }
    }
    static func validHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty && url.user == nil && url.password == nil
    }
    func isInternal(_ url: URL) -> Bool {
        guard let base, Self.validHTTPS(url) else { return false }
        return base.host?.lowercased() == url.host?.lowercased() && (base.port ?? 443) == (url.port ?? 443)
    }
    func resolve(_ path: String) -> URL? {
        guard let base, let url = URL(string: path, relativeTo: base)?.absoluteURL, isInternal(url) else { return nil }
        return url
    }
    static func externalAllowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return validHTTPS(url)
        case "mailto", "tel", "sms", "geo": return true
        default: return false
        }
    }
    static func path(_ value: String) -> String {
        let url = URL(string: value)
        let raw: String
        if let fragment = url?.fragment, fragment.hasPrefix("/") { raw = fragment.components(separatedBy: "?")[0] }
        else { raw = url?.path ?? value.components(separatedBy: "?")[0] }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : "/" + trimmed
    }
    static func matches(_ url: String, _ target: String) -> Bool {
        let current = path(url), expected = path(target)
        return current == expected || (expected != "/" && current.hasPrefix(expected + "/"))
    }
}
