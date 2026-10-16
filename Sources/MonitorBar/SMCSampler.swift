import Foundation
import IOKit

/// 通过 IOKit 直接读 AppleSMC 的键值。
/// 优先在采样线程里串行调用；状态在内部静态变量里维护，进程内只开一次连接。
///
/// 注意：键名因机型而异。Intel Mac 常见 CPU 温度键：
///   TC0P — CPU 0 Proximity（最常用，最稳）
///   TC0D — CPU 0 Die
///   TC0E — CPU 0 ???
///   TCSA — System Agent
/// Apple Silicon 上 AppleSMC 也存在但键名（Tp09/Tp01…）和格式不同，这里覆盖 Intel；
/// Apple Silicon 读不到时返回 nil，UI 自动隐藏温度段。
enum SMCSampler {
    private typealias SMCBytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    /// SMCParamStruct 的内存布局：4+2+4+4+1+3+32 = 50 字节，按 UInt32 对齐到 4 字节为 52。
    /// 跟 AppleSMCUserClient 通信时按 stride 52 传。
    private struct SMCParamStruct {
        var key: UInt32 = 0
        var padding1: UInt16 = 0
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        var padding2: (UInt8, UInt8, UInt8) = (0, 0, 0)
        var data: SMCBytes = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private static let kCallReadKey: UInt32 = 5
    private static let kCallGetKeyInfo: UInt32 = 9

    /// 进程内共享一个连接，初始化失败后不再重试
    private static var connection: io_connect_t = 0
    private static var openFailed = false

    private static func ensureOpen() -> Bool {
        if connection != 0 { return true }
        if openFailed { return false }
        let mainPort = kIOMainPortDefault
        let service = IOServiceGetMatchingService(mainPort, IOServiceMatching("AppleSMC"))
        if service == 0 {
            openFailed = true
            return false
        }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        if kr != KERN_SUCCESS {
            openFailed = true
            connection = 0
            return false
        }
        return true
    }

    private static func fourCC(_ s: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in s.utf8.prefix(4) {
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    private static func decodeType(_ raw: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((raw >> 24) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8(raw & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    private static func call(function: UInt32, input: inout SMCParamStruct,
                             output: inout SMCParamStruct) -> kern_return_t {
        var size = MemoryLayout<SMCParamStruct>.stride
        return IOConnectCallStructMethod(
            connection, function,
            &input, MemoryLayout<SMCParamStruct>.stride,
            &output, &size
        )
    }

    /// 读一个 SMC 键，失败返回 nil。
    /// macOS 15+ 对未授权的进程返回 kIOReturnNotPermitted(-536870201)，
    /// 是预期行为，全部静默处理，UI 退到热状态兜底。
    static func read(_ key: String) -> Double? {
        guard ensureOpen() else { return nil }
        let cc = fourCC(key)

        // 1) GetKeyInfo：拿 dataSize / dataType
        var infoIn = SMCParamStruct()
        infoIn.key = cc
        var infoOut = SMCParamStruct()
        let infoKr = call(function: kCallGetKeyInfo, input: &infoIn, output: &infoOut)
        guard infoKr == KERN_SUCCESS else { return nil }
        let dataSize = Int(infoOut.dataSize)
        let dataType = decodeType(infoOut.dataType)
        guard dataSize > 0, dataSize <= 32 else { return nil }

        // 2) ReadKey：取实际值
        var readIn = SMCParamStruct()
        readIn.key = cc
        readIn.dataSize = UInt32(dataSize)
        var readOut = SMCParamStruct()
        let readKr = call(function: kCallReadKey, input: &readIn, output: &readOut)
        guard readKr == KERN_SUCCESS else { return nil }

        // 3) 把 tuple 拆成 [UInt8] 方便按类型解析
        let m = readOut.data
        let bytes: [UInt8] = [
            m.0, m.1, m.2, m.3, m.4, m.5, m.6, m.7,
            m.8, m.9, m.10, m.11, m.12, m.13, m.14, m.15,
            m.16, m.17, m.18, m.19, m.20, m.21, m.22, m.23,
            m.24, m.25, m.26, m.27, m.28, m.29, m.30, m.31
        ]

        // 4) 按 dataType 解析
        switch dataType {
        case "sp78", "fpe2":
            // 7.8 / 14.2 定点，2 字节大端有符号
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw)) / 256.0
        case "ui8 ": return Double(bytes[0])
        case "ui16": return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        case "ui32":
            let v = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
                  | (UInt32(bytes[2]) << 8)  |  UInt32(bytes[3])
            return Double(v)
        case "si8 ": return Double(Int8(bitPattern: bytes[0]))
        case "si16":
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw))
        case "si32":
            let v = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
                  | (UInt32(bytes[2]) << 8)  |  UInt32(bytes[3])
            return Double(Int32(bitPattern: v))
        case "flt ":
            let v = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
                  | (UInt32(bytes[2]) << 8)  |  UInt32(bytes[3])
            return Double(Float(bitPattern: v))
        default:
            return nil
        }
    }

    /// 读 CPU 温度（°C）。按优先级尝试多个键，第一个合理值就返回。
    static func cpuTemperatureC() -> Double? {
        for key in ["TC0P", "TC0D", "TC0E", "TCSA", "TCAH", "TCAD"] {
            if let t = read(key), t > 0, t < 150 { return t }
        }
        return nil
    }
}
