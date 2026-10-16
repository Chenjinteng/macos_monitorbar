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

    static let memoryApp = Color(red: 0.30, green: 0.55, blue: 0.95)
    static let memoryWired = Color(red: 0.62, green: 0.42, blue: 0.90)
    static let memoryCompressed = Color(red: 0.20, green: 0.72, blue: 0.72)
    static let memoryCached = Color(red: 0.58, green: 0.62, blue: 0.68)
    static let memoryFree = Color(red: 0.30, green: 0.62, blue: 0.36)
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
