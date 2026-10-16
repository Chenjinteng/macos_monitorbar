import AppKit
import SwiftUI

/// 把下拉面板离屏渲染成 PNG，用来在不依赖屏幕录制权限的情况下检查 UI。
/// 用法: MonitorBar --render-preview /tmp/preview.png
@MainActor
enum PreviewRenderer {
    static func render(path: String, waitSeconds: Double = 0.8) {
        let sampler = SystemSampler()
        _ = sampler.snapshot()                       // 建立 tick 基线
        Thread.sleep(forTimeInterval: waitSeconds)

        let model = SystemMonitorModel()
        model.preferences.showSwap = true
        model.apply(sampler.snapshot())

        let view = MenuBarPanel(model: model)
            .flatBody
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        write(content: view, path: path)
    }

    /// 渲染菜单栏文字本身，确认 label 里两组内容都真实存在。
    /// 当前 NSStatusItem + NSAttributedString 路线无法离屏渲染，此方法保留作未来调试用。
    @available(*, unavailable, message: "新版本菜单栏 label 走 NSAttributedString，无法离屏渲染")
    static func renderLabel(path: String, waitSeconds: Double = 0.8) { }

    private static func write<Content: View>(content: Content, path: String) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = true

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("渲染失败\n".utf8))
            exit(1)
        }

        let url = URL(fileURLWithPath: path)
        do {
            try png.write(to: url)
            print("预览已写入 \(url.path)  (\(Int(image.size.width)) × \(Int(image.size.height)))")
        } catch {
            FileHandle.standardError.write(Data("写入失败: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}
