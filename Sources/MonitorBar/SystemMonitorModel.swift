import Foundation
import Observation
import ServiceManagement

/// 用户偏好，写入 UserDefaults 持久化。
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let showCPU = "showCPU"
        static let showMemory = "showMemory"
        static let showSwap = "showSwap"
        static let showTemperature = "showTemperature"
        static let launchAtLogin = "launchAtLogin"
    }

    private let defaults: UserDefaults

    var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    var showCPU: Bool {
        didSet { defaults.set(showCPU, forKey: Key.showCPU) }
    }

    var showMemory: Bool {
        didSet { defaults.set(showMemory, forKey: Key.showMemory) }
    }

    var showSwap: Bool {
        didSet { defaults.set(showSwap, forKey: Key.showSwap) }
    }

    var showTemperature: Bool {
        didSet { defaults.set(showTemperature, forKey: Key.showTemperature) }
    }

    var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    /// 开机启动切换失败时的提示，nil 表示没有待展示的错误。
    var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = Preferences.registeredIntervals.first ?? 1.0
        refreshInterval = defaults.object(forKey: Key.refreshInterval) as? Double ?? fallback
        showCPU = defaults.object(forKey: Key.showCPU) as? Bool ?? true
        showMemory = defaults.object(forKey: Key.showMemory) as? Bool ?? true
        showSwap = defaults.object(forKey: Key.showSwap) as? Bool ?? false
        showTemperature = defaults.object(forKey: Key.showTemperature) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    static let registeredIntervals: [Double] = [0.5, 1, 2, 5]

    private func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .enabled { return }
                try service.register()
            } else {
                if service.status == .notRegistered { return }
                try service.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "设置失败：\(error.localizedDescription)"
            // 回滚 UI 开关
            launchAtLogin = service.status == .enabled
        }
    }
}

/// 定时采样的驱动模型。采样在后台 Task 里做，结果跳回主线程更新 UI。
@MainActor
@Observable
final class SystemMonitorModel {
    var snapshot: SystemSnapshot = SystemSnapshot()

    /// 尚未拿到第一份有效数据前为 true，此时 UI 显示占位而不是 0。
    private(set) var isReady = false

    let preferences: Preferences

    private var sampler = SystemSampler()
    private var loop: Task<Void, Never>?

    var refreshInterval: Double { preferences.refreshInterval }

    init(preferences: Preferences? = nil) {
        let prefs = preferences ?? Preferences()
        self.preferences = prefs
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let sampler = self.sampler
                let result = await Task.detached(priority: .utility) { sampler.snapshot() }.value
                self.apply(result)

                let seconds = self.refreshInterval
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    /// 写入一帧采样结果。首帧到达后才把 isReady 置位，UI 在此之前显示占位符。
    func apply(_ snap: SystemSnapshot) {
        snapshot = snap
        isReady = true
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func restartIfNeeded() {
        stop()
        start()
    }
}
