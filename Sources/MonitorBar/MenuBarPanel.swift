import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @Bindable var model: SystemMonitorModel

    private var prefs: Preferences { model.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            DividerLine()
            ScrollView {
                panelBody
            }
            .frame(maxHeight: 460)

            DividerLine()
            footer
        }
        .frame(width: 306)
        .onChange(of: model.refreshInterval) { _, _ in model.restartIfNeeded() }
    }

    /// 不套 ScrollView 的扁平版本，只给离屏预览用
    /// （ImageRenderer 无法渲染滚动容器的内容，直接渲染会被画成空白）。
    var flatBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            DividerLine()
            panelBody
            DividerLine()
            footer
        }
        .frame(width: 306)
    }

    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            cpuSection
            if prefs.showTemperature { temperatureSection }
            memorySection
            if prefs.showSwap { swapSection }
            DividerLine()
            settingsSection
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("MonitorBar")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    model.restartIfNeeded()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("立即刷新")
            }
            HStack(spacing: 4) {
                Text(ProcessInfo.processInfo.hostName)
                Text("·")
                Text("运行 \(Format.uptime(ProcessInfo.processInfo.systemUptime))")
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 9)
    }

    // MARK: CPU

    private var cpuSection: some View {
        PanelRow(title: "CPU", trailing: trailingUsage(model.snapshot.cpuOverall)) {
            HStack(alignment: .center, spacing: 14) {
                RingGauge(percent: model.snapshot.cpuOverall, lineWidth: 7)
                    .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 5) {
                    if !model.isReady {
                        Text("等待采样…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if model.snapshot.cpuCores.isEmpty {
                        Text("每核心数据不可用")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("每核心负载 · \(model.snapshot.cpuCores.count) 核")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                            ForEach(Array(model.snapshot.cpuCores.enumerated()), id: \.offset) { index, value in
                                CoreBar(percent: value)
                                    .help("核心 \(index)  \(Format.percent(value))")
                            }
                        }
                        let load = model.snapshot.loadAverage
                        Text("负载 " + String(format: "%.2f  %.2f  %.2f", load[0], load[1], load[2]))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 内存

    private var memorySection: some View {
        let mem = model.snapshot.memory
        return PanelRow(title: "内存", trailing: memoryTrailing(mem)) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 14) {
                    RingGauge(percent: mem.usedRatio * 100, lineWidth: 7)
                        .frame(width: 62, height: 62)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Format.bytes(mem.used)) / \(Format.bytes(mem.total))")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        if mem.total > 0 {
                            Text("空闲 \(Format.bytes(mem.free)) · 可清除 \(Format.bytes(mem.cached))")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("等待采样…")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SegmentedBar(segments: memorySegments(mem))
                legend(mem)
            }
        }
    }

    private func memorySegments(_ mem: MemorySample) -> [(ratio: Double, color: Color)] {
        let total = max(mem.total, 1)
        func r(_ v: UInt64) -> Double { Double(v) / Double(total) }
        var out: [(Double, Color)] = [
            (r(mem.app), .memoryApp),
            (r(mem.wired), .memoryWired),
            (r(mem.compressed), .memoryCompressed),
            (r(mem.cached), .memoryCached),
            (r(mem.free), .memoryFree)
        ]
        // 采样误差可能让总和略微超过 100%，压缩空闲段避免溢出
        let sum = out.reduce(0) { $0 + $1.0 }
        if sum > 1, let freeIndex = out.indices.last {
            out[freeIndex].0 = max(0, out[freeIndex].0 - (sum - 1))
        }
        return out
    }

    private func legend(_ mem: MemorySample) -> some View {
        let items: [(String, UInt64, Color)] = [
            ("应用", mem.app, .memoryApp),
            ("联动", mem.wired, .memoryWired),
            ("压缩", mem.compressed, .memoryCompressed),
            ("缓存", mem.cached, .memoryCached),
            ("空闲", mem.free, .memoryFree)
        ]
        return FlowLayout(spacing: 10) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 4) {
                    Circle().fill(item.2).frame(width: 6, height: 6)
                    Text(item.0)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(Format.bytes(item.1))
                        .font(.system(size: 9, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: 温度

    private var temperatureSection: some View {
        let temp = model.snapshot.cpuTemperatureC
        return PanelRow(title: "温度", trailing: tempTrailing(temp)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    if let temp {
                        Text(String(format: "%.0f", temp))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.temperatureColor(temp))
                        Text("°C")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        // SMC 读不到（macOS 15+ 没拿到 temperature-monitoring entitlement），用热状态兜底
                        Text(model.snapshot.thermalState.displayName)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(model.snapshot.thermalState.color)
                    }
                    Spacer()
                    Text(tempLabel(temp))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tempBadgeColor(temp).opacity(0.18)))
                        .foregroundStyle(tempBadgeColor(temp))
                }
                if let temp {
                    TemperatureBar(celsius: temp, range: 30...100,
                                  color: Color.temperatureColor(temp))
                } else {
                    ThermalStateBar(state: model.snapshot.thermalState)
                }
                Text(tempFootnote)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tempLabel(_ c: Double?) -> String {
        if let c {
            switch c {
            case ..<50: "凉"
            case ..<70: "温"
            case ..<85: "热"
            default:    "烫"
            }
        } else {
            switch model.snapshot.thermalState {
            case .nominal:  "正常"
            case .fair:     "温热"
            case .serious:  "过热"
            case .critical: "烫手"
            @unknown default: "未知"
            }
        }
    }

    private func tempBadgeColor(_ c: Double?) -> Color {
        if let c { return Color.temperatureColor(c) }
        return model.snapshot.thermalState.color
    }

    private var tempFootnote: String {
        if model.snapshot.cpuTemperatureC != nil {
            return "CPU 接近温度 · 阈值 60/80 °C"
        } else {
            return "实际 °C 需要 `temperature-monitoring` entitlement，当前仅热状态"
        }
    }

    private func tempTrailing(_ c: Double?) -> String {
        guard model.isReady else { return "—" }
        if let c { return String(format: "%.0f°C", c) }
        return model.snapshot.thermalState.displayName
    }

    // MARK: 交换空间

    private var swapSection: some View {
        PanelRow(
            title: "交换空间",
            trailing: Format.bytes(model.snapshot.memory.swapUsed)
        ) {
            VStack(alignment: .leading, spacing: 6) {
                CoreBar(percent: model.snapshot.memory.swapRatio * 100, height: 6)
                Text("共 \(Format.bytes(model.snapshot.memory.swapTotal))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 设置

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("设置")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Text("刷新间隔")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { prefs.refreshInterval },
                    set: { prefs.refreshInterval = $0 }
                )) {
                    ForEach(Preferences.registeredIntervals, id: \.self) { value in
                        Text(intervalLabel(value)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }

            toggle("菜单栏显示 CPU", isOn: binding(\.showCPU))
            toggle("菜单栏显示内存", isOn: binding(\.showMemory))
            toggle("面板显示温度", isOn: binding(\.showTemperature))
            toggle("面板显示交换空间", isOn: binding(\.showSwap))
            toggle("开机自动启动", isOn: binding(\.launchAtLogin))

            if let error = prefs.launchAtLoginError {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { prefs[keyPath: keyPath] = $0 }
        )
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 11))
    }

    private func intervalLabel(_ value: Double) -> String {
        value == floor(value) ? "\(Int(value)) 秒" : String(format: "%.1f 秒", value)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                NSWorkspace.shared.open(url)
            } label: {
                Text("活动监视器")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color.accentColor)
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("退出")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color.accentColor)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: 辅助

    private func trailingUsage(_ percent: Double) -> String {
        model.isReady ? Format.percent(percent) : "—"
    }

    private func memoryTrailing(_ mem: MemorySample) -> String {
        guard model.isReady, mem.total > 0 else { return "—" }
        return Format.percent(mem.usedRatio * 100)
    }
}

/// 自动换行的横向布局，用于图例。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + 4
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + 4
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
