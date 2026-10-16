import Foundation

/// 一次完整采样的结果。所有字段都是 Sendable，方便在后台线程采样后跳回主线程。
struct SystemSnapshot: Sendable {
    var cpuOverall: Double = 0        // 0...100
    var cpuCores: [Double] = []       // 每个逻辑核心 0...100
    var memory: MemorySample = .zero
    var loadAverage: [Double] = [0, 0, 0]
    var date: Date = .now
}

struct MemorySample: Sendable, Equatable {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var app: UInt64 = 0        // 应用内存 App Memory
    var wired: UInt64 = 0      // 联动内存 Wired
    var compressed: UInt64 = 0 // 压缩内存 Compressed
    var cached: UInt64 = 0     // 可清除缓存
    var free: UInt64 = 0       // 空闲
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0

    static let zero = MemorySample()

    /// 0...1，已用占物理内存比例
    var usedRatio: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }

    /// 0...1，已用交换空间比例
    var swapRatio: Double {
        guard swapTotal > 0 else { return 0 }
        return Double(swapUsed) / Double(swapTotal)
    }
}
