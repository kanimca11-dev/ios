import Foundation
import Combine
import WebKit

@MainActor
final class ShellStore: ObservableObject {
    @Published private(set) var active: WebSession?
    @Published private(set) var selected = "home"
    @Published var launchFinished = false
    @Published var unlocked = false
    private var config: AppConfig?
    private var sessions: [String: WebSession] = [:]
    private var usage: [String] = []
    private struct Snapshot { let url: URL; let state: Any?; let scroll: [String: Int] }
    private var snapshots: [String: Snapshot] = [:]
    private var pendingNavigation: String?
    private var backgroundAt: Date?
    private var launchDeadline: DispatchWorkItem?
    var tabs: [NavigationTab] {
        guard let config else { return [] }
        let policy = NavigationPolicy(config.targetUrl)
        var paths = Set<String>()
        return Array(config.features.navigationTabs.filter { policy.resolve($0.path) != nil && paths.insert($0.path).inserted }.prefix(5))
    }
    func update(_ fresh: AppConfig) {
        let changedOrigin = config.map { old in
            guard let oldURL = NavigationPolicy(old.targetUrl).base, let newURL = NavigationPolicy(fresh.targetUrl).base else { return true }
            return !NavigationPolicy(oldURL.absoluteString).isInternal(newURL)
        } ?? false
        if changedOrigin { sessions.values.forEach { $0.dispose() }; sessions.removeAll(); snapshots.removeAll(); usage.removeAll(); active = nil; selected = "home" }
        if fresh.features.enableBiometrics && config?.features.enableBiometrics != true { unlocked = false }
        if !fresh.features.enableBiometrics { unlocked = true }
        config = fresh
        sessions.values.forEach { $0.config = fresh; $0.interactive = unlocked && $0 === active }
        guard fresh.isActive && fresh.isSubscriptionActive else {
            sessions.values.forEach { $0.dispose() }; sessions.removeAll(); usage.removeAll(); snapshots.removeAll(); active = nil
            finishLaunch(); return
        }
        if fresh.features.enableBiometrics && !unlocked { finishLaunch(); return }
        guard NavigationPolicy(fresh.targetUrl).base != nil else { finishLaunch(); return }
        if active == nil {
            let saved = UserDefaults.standard.string(forKey: "native_last_tab_" + fresh.targetUrl)
            select(saved.flatMap { candidate in tabs.contains(where: { $0.path == candidate }) ? candidate : nil } ?? "home")
        }
        if let pending = pendingNavigation { pendingNavigation = nil; navigate(pending) }
    }
    func didUnlock() { unlocked = true; if let config { update(config) } }
    func select(_ requested: String) {
        guard let config, unlocked, config.isActive, config.isSubscriptionActive else { return }
        let policy = NavigationPolicy(config.targetUrl)
        guard let home = policy.resolve(config.startUrl ?? config.targetUrl) ?? policy.base else { return }
        let homeKey = tabs.filter { NavigationPolicy.matches(home.absoluteString, $0.path) }
            .max(by: { NavigationPolicy.path($0.path).count < NavigationPolicy.path($1.path).count })?.path ?? "home"
        let key = requested == "home" ? homeKey : requested
        var destination: URL
        if key == homeKey { destination = home }
        else { guard let tab = tabs.first(where: { $0.path == key }), let url = policy.resolve(tab.path) else { return }; destination = url }
        if sessions[key] == nil, active == nil,
           UserDefaults.standard.string(forKey: "native_last_tab_" + config.targetUrl) == key,
           let last = UserDefaults.standard.string(forKey: "native_last_url_" + config.targetUrl), let restored = policy.resolve(last) {
            destination = restored
        }
        if selected == key, let active { active.scrollToTop(); return }
        usage.removeAll { $0 == key }; usage.append(key)
        if sessions[key] == nil {
            if sessions.count >= 3, let oldest = usage.first(where: { sessions[$0] != nil && $0 != key }), let evicted = sessions.removeValue(forKey: oldest) {
                if let url = URL(string: evicted.currentURL), policy.isInternal(url) {
                    snapshots[oldest] = Snapshot(url: url, state: evicted.webView.interactionState, scroll: evicted.scrollPosition)
                }
                if snapshots.count > 5, let key = snapshots.keys.first { snapshots.removeValue(forKey: key) }
                evicted.dispose()
                usage.removeAll { $0 == oldest }
            }
            let saved = snapshots.removeValue(forKey: key)
            let session = WebSession(config: config, url: saved?.url ?? destination, interactionState: saved?.state, scroll: saved?.scroll)
            session.onReady = { [weak self] in self?.finishLaunch() }
            session.onNativeNavigate = { [weak self] path in self?.navigate(path) }
            sessions[key] = session
        }
        active?.interactive = false
        selected = key
        active = sessions[key]
        active?.interactive = true
        if !launchFinished && launchDeadline == nil {
            let deadline = DispatchWorkItem { [weak self] in self?.finishLaunch() }
            launchDeadline = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: deadline)
        }
    }
    func navigate(_ path: String) {
        guard config != nil && unlocked else { pendingNavigation = String(path.prefix(4096)); return }
        guard let config, let url = NavigationPolicy(config.targetUrl).resolve(path) else { return }
        active?.navigate(url.absoluteString)
    }
    func finishLaunch() { launchFinished = true; launchDeadline?.cancel(); launchDeadline = nil }
    func background() { backgroundAt = Date(); sessions.values.forEach { $0.interactive = false } }
    func foreground() {
        if let config, config.features.enableBiometrics, let date = backgroundAt, Date().timeIntervalSince(date) > 30 { unlocked = false }
        active?.interactive = unlocked
        backgroundAt = nil
    }
    func rememberSelection() {
        // Persist only bounded same-origin URLs/scroll, never page storage or credentials.
        guard let config else { return }
        let key = "native_last_url_" + config.targetUrl
        if let url = active?.currentURL, let parsed = URL(string: url), NavigationPolicy(config.targetUrl).isInternal(parsed) {
            UserDefaults.standard.set(url, forKey: key)
            UserDefaults.standard.set(selected, forKey: "native_last_tab_" + config.targetUrl)
        }
    }
}
