import SwiftUI

// MARK: - 配色

extension Color {
    /// 负载配色：<55% 绿，<80% 黄，其余红
    static func loadColor(_ percent: Double) -> Color {
        switch percent {
        case ..<55: Color(red: 0.20, green: 0.72, blue: 0.44)
        case ..<80: Color(red: 0.95, green: 0.72, blue: 0.20)
        default: Color(red: 0.90, green: 0.32, blue: 0.28)
        }
    }

    static func loadGradient(_ percent: Double) -> AngularGradient {
        let base = Color.loadColor(percent)
        return AngularGradient(
            colors: [base.opacity(0.65), base, base.opacity(0.85)],
            center: .center
        )
    }

    /// CPU 温度配色，<50 凉，<70 温，<85 热，≥85 烫
    static func temperatureColor(_ c: Double) -> Color {
        switch c {
        case ..<50: Color(red: 0.20, green: 0.72, blue: 0.44)   // 绿
        case ..<70: Color(red: 0.95, green: 0.72, blue: 0.20)   // 黄
        case ..<85: Color(red: 0.95, green: 0.50, blue: 0.20)   // 橙
        default:    Color(red: 0.90, green: 0.32, blue: 0.28)   // 红
        }
    }

    static let memoryApp = Color(red: 0.30, green: 0.55, blue: 0.95)
    static let memoryWired = Color(red: 0.62, green: 0.42, blue: 0.90)
    static let memoryCompressed = Color(red: 0.20, green: 0.72, blue: 0.72)
    static let memoryCached = Color(red: 0.58, green: 0.62, blue: 0.68)
    static let memoryFree = Color(red: 0.30, green: 0.62, blue: 0.36)
}

extension ProcessInfo.ThermalState {
    /// 中文显示
    var displayName: String {
        switch self {
        case .nominal:  "正常"
        case .fair:     "温热"
        case .serious:  "过热"
        case .critical: "烫手"
        @unknown default: "未知"
        }
    }

    /// 热状态配色（4 档）
    var color: Color {
        switch self {
        case .nominal:  Color(red: 0.20, green: 0.72, blue: 0.44)
        case .fair:     Color(red: 0.95, green: 0.72, blue: 0.20)
        case .serious:  Color(red: 0.95, green: 0.50, blue: 0.20)
        case .critical: Color(red: 0.90, green: 0.32, blue: 0.28)
        @unknown default: Color.gray
        }
    }

    /// 热状态对应的 0...1 位置，用来画通用条
    var barRatio: Double {
        switch self {
        case .nominal:  0.20
        case .fair:     0.50
        case .serious:  0.75
        case .critical: 0.95
        @unknown default: 0.20
        }
    }
}

/// 4 档热状态条：把 nominal/fair/serious/critical 画成一格一格的胶囊
struct ThermalStateBar: View {
    let state: ProcessInfo.ThermalState
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let active = isActive(level: i)
                    Capsule()
                        .fill(active ? state.color : Color.primary.opacity(0.08))
                        .frame(maxWidth: .infinity, maxHeight: height)
                }
            }
        }
        .frame(height: height)
    }

    private func isActive(level: Int) -> Bool {
        let current: Int
        switch state {
        case .nominal:  current = 0
        case .fair:     current = 1
        case .serious:  current = 2
        case .critical: current = 3
        @unknown default: current = 0
        }
        return level <= current
    }
}

// MARK: - 格式化

enum Format {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useGB, .useMB]
        f.includesUnit = true
        f.zeroPadsFractionDigits = false
        return f
    }()

    static func bytes(_ value: UInt64) -> String {
        bytes.string(fromByteCount: Int64(clamping: value))
    }

    static func percent(_ value: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", value)
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let d = total / 86_400
        let h = (total % 86_400) / 3_600
        let m = (total % 3_600) / 60
        if d > 0 { return "\(d) 天 \(h) 小时" }
        if h > 0 { return "\(h) 小时 \(m) 分钟" }
        return "\(m) 分钟"
    }
}

// MARK: - 环形仪表

struct RingGauge: View {
    let percent: Double
    var lineWidth: CGFloat = 7
    var showsCaption: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.004, min(1, percent / 100)))
                .stroke(
                    Color.loadGradient(percent),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if showsCaption {
                VStack(spacing: 0) {
                    Text(Format.percent(percent))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("占用")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(lineWidth / 2)
    }
}

// MARK: - 线性分项条

struct SegmentedBar: View {
    let segments: [(ratio: Double, color: Color)]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    Rectangle()
                        .fill(seg.color)
                        .frame(width: max(0, (geo.size.width - 0.5 * Double(segments.count - 1)) * seg.ratio))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        }
        .frame(height: height)
    }
}

/// 单条水平进度条（用于每核心负载）
struct CoreBar: View {
    let percent: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.loadColor(percent))
                    .frame(width: max(0, geo.size.width * min(1, max(0, percent / 100))))
            }
        }
        .frame(height: height)
    }
}

/// 温度刻度条：30–100°C 范围，当前值填色，60/80 处画阈值刻度
struct TemperatureBar: View {
    let celsius: Double
    let range: ClosedRange<Double>
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: fillWidth(geo.size.width))
                ForEach([60.0, 80.0], id: \.self) { threshold in
                    let x = position(of: threshold, width: geo.size.width)
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1, height: height + 4)
                        .offset(x: x, y: 0)
                }
            }
        }
        .frame(height: height)
    }

    private func position(of value: Double, width: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return CGFloat((clamped - range.lowerBound) / span) * width
    }

    private func fillWidth(_ width: CGFloat) -> CGFloat {
        position(of: celsius, width: width)
    }
}

// MARK: - 面板行容器

struct PanelRow<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
            content
        }
    }
}

struct PanelSection<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}
