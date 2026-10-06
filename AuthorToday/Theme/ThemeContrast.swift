import SwiftUI
import UIKit

/// Estimates how light/dark a theme backdrop is so chrome ink stays readable.
enum ThemeContrast {
    private static let lock = NSLock()
    private static var luminanceCache: [String: CGFloat] = [:]

    /// Relative luminance 0…1 (WCAG). Higher = lighter.
    static func averageLuminance(imageNamed name: String) -> CGFloat {
        lock.lock()
        defer { lock.unlock() }
        if let cached = luminanceCache[name] { return cached }
        let value = UIImage(named: name).map(sampleLuminance) ?? 0.35
        luminanceCache[name] = value
        return value
    }

    static func relativeLuminance(of color: Color) -> CGFloat {
        sampleLuminance(UIColor(color))
    }

    /// Backdrop luminance after the atmosphere scrim (what labels actually sit on).
    static func effectiveBackdropLuminance(for preset: AppThemePreset) -> CGFloat {
        if let name = preset.backgroundImageName {
            let raw = averageLuminance(imageNamed: name)
            let strength = CGFloat(scrimStrength(rawLuminance: raw))
            if raw > lightThreshold {
                // Light wash mixes toward white → effective stays bright.
                let veil = min(0.12 + strength * 0.55, 0.45)
                return raw * (1 - veil) + 1.0 * veil
            }
            let veil = min(0.18 + strength * 0.85, 0.72)
            return raw * (1 - veil)
        }
        return relativeLuminance(of: preset.atmosphereBase)
    }

    /// Mid-grey threshold for choosing dark vs light chrome ink.
    private static let lightThreshold: CGFloat = 0.55

    /// Scrim opacity from raw photo luminance (shared by preset + effective luminance).
    static func scrimStrength(rawLuminance raw: CGFloat) -> Double {
        let r = Double(raw)
        if raw > lightThreshold {
            return min(max(0.22 + (r - 0.55) * 0.35, 0.18), 0.36)
        }
        return min(max(0.38 + (0.55 - r) * 0.25, 0.36), 0.58)
    }

    /// Pick ink that contrasts with the effective backdrop.
    static func readableInk(for preset: AppThemePreset) -> ThemeChromeInk {
        effectiveBackdropLuminance(for: preset) > 0.52 ? .onLight : .onDark
    }

    private static func sampleLuminance(_ image: UIImage) -> CGFloat {
        let side = 24
        let size = CGSize(width: side, height: side)
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        guard let rendered = UIGraphicsGetImageFromCurrentImageContext(),
              let cg = rendered.cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data)
        else {
            return 0.35
        }
        let bytesPerPixel = max(cg.bitsPerPixel / 8, 1)
        let bytesPerRow = cg.bytesPerRow
        let w = cg.width
        let h = cg.height
        var total: CGFloat = 0
        var count: CGFloat = 0
        let step = max(1, min(w, h) / 8)
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                let i = y * bytesPerRow + x * bytesPerPixel
                let r = CGFloat(ptr[i]) / 255
                let g = CGFloat(ptr[min(i + 1, CFDataGetLength(data) - 1)]) / 255
                let b = CGFloat(ptr[min(i + 2, CFDataGetLength(data) - 1)]) / 255
                total += relativeLuminance(r: r, g: g, b: b)
                count += 1
                x += step
            }
            y += step
        }
        return count > 0 ? total / count : 0.35
    }

    private static func sampleLuminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            var w: CGFloat = 0
            if color.getWhite(&w, alpha: &a) {
                return relativeLuminance(r: w, g: w, b: w)
            }
            return 0.5
        }
        return relativeLuminance(r: r, g: g, b: b)
    }

    private static func relativeLuminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
