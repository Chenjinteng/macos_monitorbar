import AppKit
import SwiftUI

@main
struct MonitorBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        if CommandLine.arguments.contains("--sample") {
            SampleCLI.runAndExit()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
           let path = Self.nextPath(after: index) {
            MainActor.assumeIsolated { PreviewRenderer.render(path: path) }
        }
        // 注: --render-label 已废弃。新版菜单栏 label 是 NSAttributedString
        // 贴在 NSStatusItem 上,SwiftUI 离屏渲染画不出来。
    }

    private static func nextPath(after index: Int) -> String? {
        let value = CommandLine.arguments[index + 1]
        return value.hasPrefix("--") ? nil : value
    }

    // 真菜单栏 UI 在 AppDelegate 里用 NSStatusItem + NSPopover 装配，
    // 这里给 SwiftUI App 一个占位 scene，避免它要求一定有 Scene。
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - AppDelegate：真正的菜单栏装配

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let model = SystemMonitorModel()
    private var refreshTimer: Timer?
    private var globalClickMonitor: Any?
    private var activeAppObserver: NSObjectProtocol?
    private var popoverShownAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1) 注册 status item
        statusItem = NSStatusBar.system.statusItem(withLength: -1)
        guard let button = statusItem.button else {
            NSLog("MonitorBar: status item 创建失败")
            return
        }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // 2) 装配 popover，内容是 SwiftUI 面板
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 306, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanel(model: model)
        )

        // 3) 启动采样 + 定时刷新按钮标题
        model.start()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatusItem() }
        }
        refreshStatusItem()

        // 4) 兜底关闭 —— NSPopover.transient 在菜单栏 app 上经常漏掉。
        //    a) NSWorkspace 通知：别的 app 变 active 就关
        activeAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissIfOurAppInactive() }
        }
        //    b) 全局鼠标监听：系统级任何左/右键落下都检查，popover 外就关
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.dismissIfClickOutside(event: event) }
        }
    }

    deinit {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let o = activeAppObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // 标记打开时间，下面两个兜底关窗器在宽限期内不动作
            // 避免"打开那次点击"被自己接住、瞬间又关掉
            popoverShownAt = Date()
        }
    }

    private func isWithinOpenGracePeriod() -> Bool {
        guard let shownAt = popoverShownAt else { return false }
        return Date().timeIntervalSince(shownAt) < 0.35
    }

    private func dismissIfOurAppInactive() {
        guard popover?.isShown == true, !isWithinOpenGracePeriod() else { return }
        if !NSApp.isActive {
            popover.performClose(nil)
        }
    }

    private func dismissIfClickOutside(event: NSEvent) {
        guard popover?.isShown == true, !isWithinOpenGracePeriod() else { return }
        guard let popoverWindow = popover?.contentViewController?.view.window else { return }
        let screen = NSEvent.mouseLocation
        if !popoverWindow.frame.contains(screen) {
            popover.performClose(nil)
        }
    }

    private func refreshStatusItem() {
        statusItem?.button?.attributedTitle = StatusItemTitleBuilder.make(model: model)
    }
}

// MARK: - 菜单栏按钮的富文本（SF Symbol + 数字）

@MainActor
enum StatusItemTitleBuilder {
    static func make(model: SystemMonitorModel) -> NSAttributedString {
        let prefs = model.preferences
        let snap = model.snapshot
        let result = NSMutableAttributedString()
        let textFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: textFont]

        if prefs.showCPU {
            appendIcon("cpu", to: result)
            result.append(NSAttributedString(string: " \(Format.percent(snap.cpuOverall))", attributes: textAttrs))
        }
        if prefs.showCPU && prefs.showMemory {
            result.append(NSAttributedString(string: "   ", attributes: textAttrs))
        }
        if prefs.showMemory {
            appendIcon("memorychip", to: result)
            result.append(NSAttributedString(string: " \(Format.bytes(snap.memory.used))", attributes: textAttrs))
        }
        return result
    }

    /// 把 SF Symbol 当作模板图直接贴进富文本，状态栏会用 label 色（黑/白）渲染。
    private static func appendIcon(_ name: String,
                                   to result: NSMutableAttributedString) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            let fallback = name == "cpu" ? "⚙︎" : "▣"
            result.append(NSAttributedString(string: fallback,
                attributes: [.font: NSFont.systemFont(ofSize: 12)]))
            return
        }
        let size = NSSize(width: 15, height: 13)
        let attachment = NSTextAttachment()
        attachment.image = symbol
        attachment.bounds = NSRect(x: 0, y: -2.5, width: size.width, height: size.height)
        result.append(NSAttributedString(attachment: attachment))
    }
}

// MARK: - 命令行自检

enum SampleCLI {
    static func runAndExit() -> Never {
        let sampler = SystemSampler()
        let host = ProcessInfo.processInfo.hostName

        print("MonitorBar 采样自检 — \(host)")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print(String(repeating: "─", count: 60))

        for round in 1...3 {
            Thread.sleep(forTimeInterval: 1.0)
            let s = sampler.snapshot()
            let mem = s.memory
            let coreText = s.cpuCores.isEmpty
                ? "每核心不可用"
                : "每核心 [" + s.cpuCores.map { String(format: "%3.0f", $0) }.joined(separator: " ") + "]"
            print(String(format: "[%d] CPU %5.1f%%  %@", round, s.cpuOverall, coreText))
            print(String(format: "     内存 %@ / %@ (%.1f%%)  应用 %@ · 联动 %@ · 压缩 %@ · 缓存 %@ · 空闲 %@",
                         Format.bytes(mem.used), Format.bytes(mem.total), mem.usedRatio * 100,
                         Format.bytes(mem.app), Format.bytes(mem.wired), Format.bytes(mem.compressed),
                         Format.bytes(mem.cached), Format.bytes(mem.free)))
            print(String(format: "     交换 %@ / %@  负载 %.2f %.2f %.2f",
                         Format.bytes(mem.swapUsed), Format.bytes(mem.swapTotal),
                         s.loadAverage[0], s.loadAverage[1], s.loadAverage[2]))
            if let t = s.cpuTemperatureC {
                print(String(format: "     CPU 温度 %.0f°C", t))
            } else {
                print("     CPU 温度 不可用（SMC 读不到）")
            }
        }

        print(String(repeating: "─", count: 60))
        print("采样正常。")
        exit(0)
    }
}
