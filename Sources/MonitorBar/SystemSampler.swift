import Darwin
import Foundation

// MARK: - CPU

struct CPUTicks: Sendable {
    var user: UInt64 = 0
    var system: UInt64 = 0
    var idle: UInt64 = 0
    var nice: UInt64 = 0

    var busy: UInt64 { user + system + nice }
    var all: UInt64 { busy + idle }

    /// 从 old 到 new 这段区间内的忙碌占比，0...1。
    /// 用 from→to 的命名，避免 old / new 传反导致无符号回绕。
    static func load(from old: CPUTicks, to new: CPUTicks) -> Double {
        let dAll = new.all &- old.all
        let dIdle = new.idle &- old.idle
        guard dAll > 0, dIdle < dAll else { return 0 }
        return Double(dAll - dIdle) / Double(dAll)
    }
}

/// `cpu_tick_info` 在 Swift 里被导入成 4 元组，按 user / system / idle / nice 排列。
private func ticks(_ tuple: (natural_t, natural_t, natural_t, natural_t)) -> CPUTicks {
    CPUTicks(user: UInt64(tuple.0), system: UInt64(tuple.1), idle: UInt64(tuple.2), nice: UInt64(tuple.3))
}

private let cpuLoadInfoWordCount = mach_msg_type_number_t(
    MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
)

/// 整机 CPU 累计 tick。
func currentCPUTicks() -> CPUTicks? {
    var count = cpuLoadInfoWordCount
    var info = host_cpu_load_info_data_t()
    let kr: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }
    return ticks(info.cpu_ticks)
}

/// 每个逻辑核心的累计 tick（Apple Silicon / Intel 都适用）。
func currentCoreTicks() -> [CPUTicks]? {
    var infoCount: mach_msg_type_number_t = 0
    var array: processor_info_array_t?
    var infoCountOut: mach_msg_type_number_t = 0

    let kr = host_processor_info(
        mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
        &infoCount, &array, &infoCountOut
    )
    guard kr == KERN_SUCCESS, let array else { return nil }

    let stride = MemoryLayout<processor_cpu_load_info>.size / MemoryLayout<integer_t>.size
    let cpuCount = Int(infoCountOut) / stride
    defer {
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: array)),
            vm_size_t(Int(infoCountOut)) * vm_size_t(MemoryLayout<integer_t>.size)
        )
    }
    guard cpuCount > 0 else { return [] }

    let buffer = UnsafeRawBufferPointer(start: array, count: cpuCount * MemoryLayout<processor_cpu_load_info>.size)
        .bindMemory(to: processor_cpu_load_info.self)

    return buffer.map { ticks($0.cpu_ticks) }
}

// MARK: - Memory

func physicalMemoryTotal() -> UInt64 {
    var value: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    guard sysctlbyname("hw.memsize", &value, &size, nil, 0) == 0 else { return 0 }
    return value
}

func currentSwapUsage() -> (total: UInt64, used: UInt64)? {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
    return (usage.xsu_total, usage.xsu_used)
}

func currentMemory() -> MemorySample? {
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    var stats = vm_statistics64()
    let kr: kern_return_t = withUnsafeMutablePointer(to: &stats) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }

    let page = UInt64(vm_kernel_page_size)
    func pages(_ n: UInt64) -> UInt64 { n &* page }

    let active = pages(UInt64(stats.active_count))
    let inactive = pages(UInt64(stats.inactive_count))
    let speculative = pages(UInt64(stats.speculative_count))
    let wired = pages(UInt64(stats.wire_count))
    // 注意：必须用 compressor_page_count（压缩器实际占用的物理页），
    // 不能用 total_uncompressed_pages_in_compressor（解压后的原始体积，可能远大于物理内存）。
    let compressed = pages(UInt64(stats.compressor_page_count))
    let rawFree = pages(UInt64(stats.free_count))

    let total = physicalMemoryTotal()
    let app = active
    let cached = inactive &+ speculative          // 可回收的文件/缓存页
    let used = app &+ wired &+ compressed        // 「已用」不含缓存
    let occupied = used &+ cached
    let free = total > occupied ? total &- occupied : rawFree

    var sample = MemorySample()
    sample.total = total
    sample.app = app
    sample.wired = wired
    sample.compressed = compressed
    sample.cached = cached
    sample.used = used
    sample.free = free
    if let swap = currentSwapUsage() {
        sample.swapTotal = swap.total
        sample.swapUsed = swap.used
    }
    return sample
}

func currentLoadAverage() -> [Double] {
    var load = [Double](repeating: 0, count: 3)
    guard getloadavg(&load, 3) == 3 else { return [0, 0, 0] }
    return load
}

// MARK: - Sampler

/// 有状态的采样器：CPU 负载必须靠两次 tick 求差，所以要记住上一次的值。
/// 只在单个后台 Task 内串行使用。
final class SystemSampler {
    private var previousOverall: CPUTicks?
    private var previousCores: [CPUTicks] = []
    private let totalMemory: UInt64

    init() {
        totalMemory = physicalMemoryTotal()
        // 预热：先读一次 tick 作为基线，第一帧 UI 就能显示真实负载而不是 0%
        previousOverall = currentCPUTicks()
        previousCores = currentCoreTicks() ?? []
    }

    func snapshot() -> SystemSnapshot {
        var snap = SystemSnapshot()
        snap.date = .now
        snap.loadAverage = currentLoadAverage()

        if let now = currentCPUTicks() {
            if let previousOverall {
                // load() 返回 0...1 的比例，对外统一暴露 0...100 的百分数
                snap.cpuOverall = CPUTicks.load(from: previousOverall, to: now) * 100
            }
            previousOverall = now
        }

        if let now = currentCoreTicks() {
            if !previousCores.isEmpty, now.count == previousCores.count {
                snap.cpuCores = zip(previousCores, now).map { CPUTicks.load(from: $0, to: $1) * 100 }
            }
            previousCores = now
        }

        var mem = currentMemory() ?? .zero
        if mem.total == 0 { mem.total = totalMemory }
        snap.memory = mem

        // SMC 读温度：失败/不存在的机型直接返回 nil，UI 用热状态兜底
        snap.cpuTemperatureC = SMCSampler.cpuTemperatureC()
        snap.thermalState = ProcessInfo.processInfo.thermalState

        return snap
    }
}
