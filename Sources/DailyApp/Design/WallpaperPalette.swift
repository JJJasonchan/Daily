import AppKit
import Observation
import SwiftUI

struct WallpaperPalette: Equatable, Sendable {
    let hue: Double
    let saturation: Double
    let brightness: Double

    static let fallback = WallpaperPalette.from(
        red: 0.52,
        green: 0.58,
        blue: 0.66
    )

    static func from(red: Double, green: Double, blue: Double) -> WallpaperPalette {
        let color = NSColor(
            calibratedRed: red.clamped(to: 0...1),
            green: green.clamped(to: 0...1),
            blue: blue.clamped(to: 0...1),
            alpha: 1
        )
        var hue = CGFloat.zero
        var saturation = CGFloat.zero
        var brightness = CGFloat.zero
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

        return WallpaperPalette(
            hue: Double(hue),
            saturation: Double(saturation).clamped(to: 0.15...0.50),
            brightness: Double(brightness).clamped(to: 0.30...0.76)
        )
    }

    var topColor: Color {
        Color(
            hue: hue,
            saturation: saturation,
            brightness: (brightness + 0.06).clamped(to: 0...0.88)
        )
    }

    var bottomColor: Color {
        Color(
            hue: hue,
            saturation: (saturation * 0.72).clamped(to: 0...1),
            brightness: (brightness - 0.08).clamped(to: 0.22...1)
        )
    }

    var cardTint: Color {
        Color(
            hue: hue,
            saturation: (saturation * 0.45).clamped(to: 0...1),
            brightness: (brightness + 0.12).clamped(to: 0...0.88)
        )
    }
}

@MainActor
protocol DesktopImageURLProviding {
    func desktopImageURL() -> URL?
}

@MainActor
protocol WallpaperImageSampling {
    func averageRGB(at url: URL) -> (red: Double, green: Double, blue: Double)?
}

@MainActor
protocol WallpaperPaletteProviding: AnyObject {
    var palette: WallpaperPalette { get }
    func refresh()
}

@MainActor
struct SystemDesktopImageURLProvider: DesktopImageURLProviding {
    func desktopImageURL() -> URL? {
        guard let screen = NSScreen.main else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }
}

@MainActor
struct SystemWallpaperImageSampler: WallpaperImageSampling {
    func averageRGB(at url: URL) -> (red: Double, green: Double, blue: Double)? {
        guard let image = NSImage(contentsOf: url),
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: 1,
                  pixelsHigh: 1,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bitmapFormat: .alphaFirst,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: 1, height: 1),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let color = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else {
            return nil
        }
        return (
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
    }
}

@MainActor
@Observable
final class WallpaperPaletteStore: WallpaperPaletteProviding {
    private(set) var palette: WallpaperPalette = .fallback

    private let urlProvider: any DesktopImageURLProviding
    private let imageSampler: any WallpaperImageSampling
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private var registrations: [WallpaperNotificationRegistration] = []

    init(
        urlProvider: any DesktopImageURLProviding = SystemDesktopImageURLProvider(),
        imageSampler: any WallpaperImageSampling = SystemWallpaperImageSampler(),
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        observesSystemChanges: Bool = true
    ) {
        self.urlProvider = urlProvider
        self.imageSampler = imageSampler
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        refresh()

        if observesSystemChanges {
            startObservingSystemChanges()
        }
    }

    func refresh() {
        guard let url = urlProvider.desktopImageURL(),
              let rgb = imageSampler.averageRGB(at: url) else {
            palette = .fallback
            return
        }
        palette = WallpaperPalette.from(
            red: rgb.red,
            green: rgb.green,
            blue: rgb.blue
        )
    }

    private func startObservingSystemChanges() {
        let appNotifications: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didChangeScreenParametersNotification
        ]
        registrations = appNotifications.map { name in
            observe(center: notificationCenter, name: name)
        }
        registrations.append(
            observe(
                center: workspaceNotificationCenter,
                name: NSWorkspace.activeSpaceDidChangeNotification
            )
        )
    }

    private func observe(
        center: NotificationCenter,
        name: Notification.Name
    ) -> WallpaperNotificationRegistration {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        return WallpaperNotificationRegistration(center: center, token: token)
    }
}

private final class WallpaperNotificationRegistration {
    private let center: NotificationCenter
    private let token: NSObjectProtocol

    init(center: NotificationCenter, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    deinit {
        center.removeObserver(token)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
