import SwiftUI

/// Animated full-screen atmosphere tied to the selected app theme.
struct ThemeAtmosphereView: View {
    let preset: AppThemePreset
    /// 0…1 — lower for compact previews in settings.
    var intensity: Double = 1
    var animated: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: animated ? 1.0 / 24.0 : 3600, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                draw(in: canvas, size: size, time: t)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: Double) {
        let i = intensity
        let base = preset.atmosphereBase
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))

        switch preset.atmosphereStyle {
        case .classic:
            drawBlobs(context: context, size: size, time: time * 0.35, colors: preset.atmosphereBlobColors, scale: 0.55 * i, count: 4)
            drawVignette(context: context, size: size, opacity: 0.18 * i)
        case .neon:
            drawBlobs(context: context, size: size, time: time * 0.55, colors: preset.atmosphereBlobColors, scale: 0.7 * i, count: 5)
            drawScanlines(context: context, size: size, time: time, opacity: 0.12 * i)
            drawVignette(context: context, size: size, opacity: 0.35 * i)
        case .plasma:
            drawBlobs(context: context, size: size, time: time * 0.7, colors: preset.atmosphereBlobColors, scale: 0.85 * i, count: 6)
            drawVignette(context: context, size: size, opacity: 0.4 * i)
        case .orbit:
            drawStars(context: context, size: size, time: time, opacity: 0.55 * i)
            drawRings(context: context, size: size, time: time, opacity: 0.45 * i)
            drawBlobs(context: context, size: size, time: time * 0.25, colors: preset.atmosphereBlobColors, scale: 0.4 * i, count: 3)
            drawVignette(context: context, size: size, opacity: 0.45 * i)
        case .hologram:
            drawBlobs(context: context, size: size, time: time * 0.4, colors: preset.atmosphereBlobColors, scale: 0.5 * i, count: 4)
            drawGrid(context: context, size: size, time: time, opacity: 0.22 * i)
            drawVignette(context: context, size: size, opacity: 0.3 * i)
        case .ion:
            drawBlobs(context: context, size: size, time: time * 0.45, colors: preset.atmosphereBlobColors, scale: 0.6 * i, count: 5)
            drawParticles(context: context, size: size, time: time, opacity: 0.5 * i)
            drawVignette(context: context, size: size, opacity: 0.32 * i)
        case .daredevil:
            drawBlobs(context: context, size: size, time: time * 0.5, colors: preset.atmosphereBlobColors, scale: 0.75 * i, count: 5)
            drawPulse(context: context, size: size, time: time, color: preset.accent, opacity: 0.35 * i)
            drawVignette(context: context, size: size, opacity: 0.55 * i)
        }
    }

    private func drawBlobs(
        context: GraphicsContext,
        size: CGSize,
        time: Double,
        colors: [Color],
        scale: Double,
        count: Int
    ) {
        guard !colors.isEmpty else { return }
        for n in 0..<count {
            let color = colors[n % colors.count]
            let phase = Double(n) * 1.7
            let cx = size.width * (0.5 + 0.38 * sin(time * 0.55 + phase))
            let cy = size.height * (0.45 + 0.32 * cos(time * 0.42 + phase * 1.3))
            let radius = min(size.width, size.height) * (0.28 + 0.12 * sin(time * 0.7 + phase)) * scale
            var path = Path()
            path.addEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
            context.fill(path, with: .color(color.opacity(0.22 + 0.08 * sin(time + phase))))
        }
    }

    private func drawScanlines(context: GraphicsContext, size: CGSize, time: Double, opacity: Double) {
        let step: CGFloat = 5
        let offset = CGFloat(time.truncatingRemainder(dividingBy: 2.0)) * step
        var y: CGFloat = -offset
        while y < size.height + step {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(Color.cyan.opacity(opacity)), lineWidth: 1)
            y += step
        }
    }

    private func drawStars(context: GraphicsContext, size: CGSize, time: Double, opacity: Double) {
        for n in 0..<48 {
            let seed = Double(n * 97)
            let x = (sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let y = (sin(seed * 78.233) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * (1.2 + Double(n % 5) * 0.35) + seed))
            let r: CGFloat = CGFloat(1.0 + Double(n % 3))
            let rect = CGRect(
                x: abs(x) * size.width,
                y: abs(y) * size.height,
                width: r,
                height: r
            )
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(opacity * twinkle)))
        }
    }

    private func drawRings(context: GraphicsContext, size: CGSize, time: Double, opacity: Double) {
        let center = CGPoint(x: size.width * 0.72, y: size.height * 0.28)
        for n in 0..<4 {
            let radius = min(size.width, size.height) * (0.18 + CGFloat(n) * 0.11)
            let rot = time * (0.15 + Double(n) * 0.05)
            var path = Path()
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .radians(rot),
                endAngle: .radians(rot + .pi * 1.4),
                clockwise: false
            )
            context.stroke(
                path,
                with: .color(preset.accent.opacity(opacity * (0.35 - Double(n) * 0.05))),
                lineWidth: 1.5
            )
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize, time: Double, opacity: Double) {
        let step: CGFloat = 28
        let drift = CGFloat(time.truncatingRemainder(dividingBy: 4.0)) * 4
        var x: CGFloat = -drift
        while x < size.width + step {
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + size.height * 0.08, y: size.height))
            context.stroke(path, with: .color(preset.accent.opacity(opacity)), lineWidth: 0.6)
            x += step
        }
        var y: CGFloat = -drift
        while y < size.height + step {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(preset.accent.opacity(opacity * 0.55)), lineWidth: 0.5)
            y += step
        }
    }

    private func drawParticles(context: GraphicsContext, size: CGSize, time: Double, opacity: Double) {
        for n in 0..<36 {
            let seed = Double(n * 53)
            let baseX = (sin(seed) * 0.5 + 0.5)
            let speed = 0.08 + Double(n % 7) * 0.02
            let y = ((time * speed) + seed * 0.01).truncatingRemainder(dividingBy: 1.0)
            let x = (baseX + 0.08 * sin(time * 0.9 + seed)).truncatingRemainder(dividingBy: 1.0)
            let r: CGFloat = CGFloat(1.5 + Double(n % 4))
            let rect = CGRect(
                x: abs(x) * size.width,
                y: (1 - abs(y)) * size.height,
                width: r,
                height: r
            )
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(opacity * 0.55)))
        }
    }

    private func drawPulse(context: GraphicsContext, size: CGSize, time: Double, color: Color, opacity: Double) {
        let beat = 0.5 + 0.5 * sin(time * 2.2)
        let radius = min(size.width, size.height) * (0.35 + 0.15 * beat)
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.35)
        var path = Path()
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(path, with: .color(color.opacity(opacity * (0.12 + 0.18 * beat))))
    }

    private func drawVignette(context: GraphicsContext, size: CGSize, opacity: Double) {
        let gradient = Gradient(stops: [
            .init(color: .clear, location: 0.35),
            .init(color: Color.black.opacity(opacity), location: 1)
        ])
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                gradient,
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.4),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.85
            )
        )
    }
}

enum ThemeAtmosphereStyle {
    case classic
    case neon
    case plasma
    case orbit
    case hologram
    case ion
    case daredevil
}

extension View {
    /// Lets the living theme atmosphere show through lists / forms / scroll views.
    func themedScreenChrome() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.clear)
    }

    /// Soft translucent wash instead of opaque system grouped background.
    func themedGroupedFill() -> some View {
        self.background {
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.22))
                .ignoresSafeArea()
        }
    }
}
