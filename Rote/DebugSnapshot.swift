import SwiftUI

#if DEBUG && os(macOS)
import AppKit

/// Writes a PNG of the main window to `ROTE_SNAPSHOT` a few seconds after
/// launch, then quits. Used to capture PR screenshots without screen-recording
/// permission. Debug builds only.
enum DebugSnapshot {
    static var requested: Bool { ProcessInfo.processInfo.environment["ROTE_SNAPSHOT"] != nil }

    @MainActor
    static func runIfRequested() async {
        guard let path = ProcessInfo.processInfo.environment["ROTE_SNAPSHOT"] else { return }
        try? await Task.sleep(for: .seconds(3))
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView?.superview ?? window.contentView,
              let layer = view.layer
        else { exit(2) }
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { exit(3) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.scaleBy(x: scale, y: scale)
        layer.render(in: ctx.cgContext)
        // Vibrancy-backed views (the sidebar) are composited by the window
        // server, so draw their children directly over a plain background.
        for effect in effectViews(in: view) where effect.bounds.width < size.width * 0.6 && effect.bounds.height > size.height * 0.5 {
            let frame = effect.convert(effect.bounds, to: view)
            ctx.cgContext.saveGState()
            ctx.cgContext.setFillColor(NSColor.windowBackgroundColor.cgColor)
            ctx.cgContext.fill(frame)
            for child in effect.subviews {
                let childFrame = child.convert(child.bounds, to: view)
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: childFrame.minX, y: childFrame.minY)
                child.layer?.render(in: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
            ctx.cgContext.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { exit(4) }
        try? data.write(to: URL(fileURLWithPath: path))
        exit(0)
    }

    @MainActor
    private static func effectViews(in root: NSView) -> [NSVisualEffectView] {
        var found: [NSVisualEffectView] = []
        for sub in root.subviews {
            if let e = sub as? NSVisualEffectView { found.append(e) } else { found += effectViews(in: sub) }
        }
        return found
    }
}
#endif
