import SwiftUI
import UIKit

/// Full-screen living theme backdrop — distinct scenes per preset (not just colored blobs).
struct ThemeAtmosphereView: View {
    let preset: AppThemePreset
    var intensity: Double = 1
    var animated: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: animated ? 1.0 / 20.0 : 3600, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                ThemeScenePainter.paint(preset: preset, context: canvas, size: size, time: t, intensity: intensity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// Draws figurative theme scenes so presets are recognizable at a glance.
enum ThemeScenePainter {
    static func paint(
        preset: AppThemePreset,
        context: GraphicsContext,
        size: CGSize,
        time: Double,
        intensity: Double
    ) {
        let i = max(0.15, min(intensity, 1))
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(preset.atmosphereBase))

        switch preset {
        case .moss:
            paintForest(context: context, size: size, time: time, accent: preset.accent, intensity: i)
        case .ocean:
            paintOcean(context: context, size: size, time: time, accent: preset.accent, intensity: i)
        case .wine:
            paintWineHall(context: context, size: size, time: time, accent: preset.accent, intensity: i)
        case .graphite:
            paintLibraryShelves(context: context, size: size, time: time, accent: preset.accent, intensity: i)
        case .sand:
            paintDunes(context: context, size: size, time: time, accent: preset.accent, intensity: i)
        case .neon:
            paintNeonCity(context: context, size: size, time: time, intensity: i)
        case .plasma:
            paintAurora(context: context, size: size, time: time, intensity: i)
        case .orbit:
            paintOrbit(context: context, size: size, time: time, accent: preset.accent, intensity: i)
        case .hologram:
            paintHologram(context: context, size: size, time: time, accent: preset.accent, intensity: i)
        case .ion:
            paintIonStorm(context: context, size: size, time: time, accent: preset.accent, intensity: i)
        case .daredevil:
            paintDaredevilRooftop(context: context, size: size, time: time, intensity: i)
        case .hellsKitchen:
            paintHellsKitchen(context: context, size: size, time: time, intensity: i)
        case .murdock:
            paintMurdockRain(context: context, size: size, time: time, intensity: i)
        case .custom:
            paintSoftWash(context: context, size: size, time: time, colors: preset.atmosphereBlobColors, intensity: i)
        }

        // Soft top/bottom wash so lists stay readable.
        var top = Path()
        top.addRect(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.22))
        context.fill(top, with: .linearGradient(
            Gradient(colors: [preset.atmosphereBase.opacity(0.55 * i), .clear]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height * 0.22)
        ))
        var bottom = Path()
        bottom.addRect(CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.28))
        context.fill(bottom, with: .linearGradient(
            Gradient(colors: [.clear, preset.atmosphereBase.opacity(0.65 * i)]),
            startPoint: CGPoint(x: 0, y: size.height * 0.72),
            endPoint: CGPoint(x: 0, y: size.height)
        ))
    }

    // MARK: - Classic scenes

    private static func paintForest(context: GraphicsContext, size: CGSize, time: Double, accent: Color, intensity: Double) {
        // Mist bands
        for n in 0..<3 {
            let y = size.height * (0.55 + Double(n) * 0.08) + sin(time * 0.4 + Double(n)) * 8
            var band = Path()
            band.addEllipse(in: CGRect(x: -40, y: y, width: size.width + 80, height: 40))
            context.fill(band, with: .color(Color.white.opacity(0.08 * intensity)))
        }
        // Tree silhouettes
        let groundY = size.height * 0.78
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: groundY))
        ground.addLine(to: CGPoint(x: size.width, y: groundY + 10))
        ground.addLine(to: CGPoint(x: size.width, y: size.height))
        ground.addLine(to: CGPoint(x: 0, y: size.height))
        context.fill(ground, with: .color(accent.opacity(0.35 * intensity)))

        for n in 0..<7 {
            let x = size.width * (0.08 + CGFloat(n) * 0.13)
            let sway = sin(time * 0.7 + Double(n)) * 4
            let h = size.height * (0.28 + CGFloat(n % 3) * 0.06)
            var trunk = Path()
            trunk.addRect(CGRect(x: x - 3 + sway, y: groundY - h, width: 6, height: h))
            context.fill(trunk, with: .color(Color(red: 0.12, green: 0.2, blue: 0.16).opacity(0.55 * intensity)))
            var canopy = Path()
            canopy.addEllipse(in: CGRect(x: x - 28 + sway, y: groundY - h - 36, width: 56, height: 52))
            context.fill(canopy, with: .color(accent.opacity(0.45 * intensity)))
        }
        // Soft sun
        let sunX = size.width * (0.78 + 0.02 * sin(time * 0.2))
        var sun = Path()
        sun.addEllipse(in: CGRect(x: sunX - 28, y: size.height * 0.18, width: 56, height: 56))
        context.fill(sun, with: .color(Color(red: 0.95, green: 0.85, blue: 0.45).opacity(0.35 * intensity)))
    }

    private static func paintOcean(context: GraphicsContext, size: CGSize, time: Double, accent: Color, intensity: Double) {
        // Sky gradient already base; moon
        var moon = Path()
        moon.addEllipse(in: CGRect(x: size.width * 0.7, y: size.height * 0.12, width: 44, height: 44))
        context.fill(moon, with: .color(Color.white.opacity(0.5 * intensity)))

        for n in 0..<5 {
            let phase = time * (0.6 + Double(n) * 0.08) + Double(n)
            let y = size.height * (0.5 + CGFloat(n) * 0.08)
            var wave = Path()
            wave.move(to: CGPoint(x: 0, y: y))
            var x: CGFloat = 0
            while x <= size.width {
                let yy = y + sin(Double(x) * 0.02 + phase) * (10 + CGFloat(n) * 2)
                wave.addLine(to: CGPoint(x: x, y: yy))
                x += 8
            }
            wave.addLine(to: CGPoint(x: size.width, y: size.height))
            wave.addLine(to: CGPoint(x: 0, y: size.height))
            context.fill(wave, with: .color(accent.opacity((0.12 + Double(n) * 0.04) * intensity)))
        }
    }

    private static func paintWineHall(context: GraphicsContext, size: CGSize, time: Double, accent: Color, intensity: Double) {
        // Curtains
        for n in 0..<6 {
            let x = size.width * CGFloat(n) / 5.5
            let sway = sin(time * 0.5 + Double(n)) * 6
            var panel = Path()
            panel.move(to: CGPoint(x: x + sway, y: 0))
            panel.addLine(to: CGPoint(x: x + size.width * 0.18 + sway, y: 0))
            panel.addLine(to: CGPoint(x: x + size.width * 0.14, y: size.height))
            panel.addLine(to: CGPoint(x: x - 10, y: size.height))
            context.fill(panel, with: .color(accent.opacity((n % 2 == 0 ? 0.28 : 0.16) * intensity)))
        }
        // Candle glow
        let glowX = size.width * 0.5 + sin(time) * 8
        var glow = Path()
        glow.addEllipse(in: CGRect(x: glowX - 50, y: size.height * 0.55, width: 100, height: 100))
        context.fill(glow, with: .color(Color(red: 1, green: 0.7, blue: 0.3).opacity(0.18 * intensity * (0.7 + 0.3 * sin(time * 3)))))
    }

    private static func paintLibraryShelves(context: GraphicsContext, size: CGSize, time: Double, accent: Color, intensity: Double) {
        for row in 0..<5 {
            let y = size.height * (0.25 + CGFloat(row) * 0.12)
            var shelf = Path()
            shelf.addRect(CGRect(x: 16, y: y, width: size.width - 32, height: 4))
            context.fill(shelf, with: .color(accent.opacity(0.35 * intensity)))
            for b in 0..<8 {
                let x = 24 + CGFloat(b) * ((size.width - 48) / 8)
                let h = 28 + CGFloat((b + row) % 4) * 6
                let pulse = 0.2 + 0.05 * sin(time + Double(b + row))
                var book = Path()
                book.addRect(CGRect(x: x, y: y - h, width: 14, height: h))
                context.fill(book, with: .color(accent.opacity(pulse * intensity)))
            }
        }
    }

    private static func paintDunes(context: GraphicsContext, size: CGSize, time: Double, accent: Color, intensity: Double) {
        for n in 0..<4 {
            let y = size.height * (0.45 + CGFloat(n) * 0.12)
            let phase = time * 0.25 + Double(n)
            var dune = Path()
            dune.move(to: CGPoint(x: 0, y: size.height))
            dune.addLine(to: CGPoint(x: 0, y: y))
            var x: CGFloat = 0
            while x <= size.width {
                let yy = y + sin(Double(x) * 0.012 + phase) * 24
                dune.addLine(to: CGPoint(x: x, y: yy))
                x += 10
            }
            dune.addLine(to: CGPoint(x: size.width, y: size.height))
            context.fill(dune, with: .color(accent.opacity((0.15 + Double(n) * 0.06) * intensity)))
        }
        var sun = Path()
        sun.addEllipse(in: CGRect(x: size.width * 0.15, y: size.height * 0.16, width: 70, height: 70))
        context.fill(sun, with: .color(Color(red: 1, green: 0.75, blue: 0.35).opacity(0.4 * intensity)))
    }

    // MARK: - Futuristic scenes

    private static func paintNeonCity(context: GraphicsContext, size: CGSize, time: Double, intensity: Double) {
        let neonA = Color(red: 0.0, green: 0.95, blue: 1.0)
        let neonB = Color(red: 1.0, green: 0.2, blue: 0.75)
        // Buildings
        for n in 0..<9 {
            let w = size.width * (0.08 + CGFloat(n % 3) * 0.02)
            let x = size.width * (0.05 + CGFloat(n) * 0.1)
            let h = size.height * (0.25 + CGFloat((n * 3) % 5) * 0.08)
            var building = Path()
            building.addRect(CGRect(x: x, y: size.height - h, width: w, height: h))
            context.fill(building, with: .color(Color(red: 0.05, green: 0.08, blue: 0.14).opacity(0.85 * intensity)))
            // Windows blink
            for wy in stride(from: size.height - h + 10, to: size.height - 20, by: 14) {
                for wx in stride(from: x + 4, to: x + w - 4, by: 10) {
                    let on = sin(time * 2 + Double(wx + wy)) > 0.2
                    if on {
                        var win = Path()
                        win.addRect(CGRect(x: wx, y: wy, width: 5, height: 7))
                        context.fill(win, with: .color((n % 2 == 0 ? neonA : neonB).opacity(0.55 * intensity)))
                    }
                }
            }
        }
        // Neon signs
        for n in 0..<3 {
            let y = size.height * (0.35 + CGFloat(n) * 0.12) + sin(time * 1.5 + Double(n)) * 3
            var sign = Path()
            sign.addRoundedRect(in: CGRect(x: size.width * 0.15, y: y, width: size.width * 0.35, height: 10), cornerSize: CGSize(width: 3, height: 3))
            context.fill(sign, with: .color((n % 2 == 0 ? neonA : neonB).opacity(0.45 * intensity)))
        }
        // Rain streaks
        for n in 0..<40 {
            let x = CGFloat((n * 97) % Int(size.width))
            let y = CGFloat((Double(n * 53) + time * 120).truncatingRemainder(dividingBy: Double(size.height)))
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - 2, y: y + 14))
            context.stroke(drop, with: .color(neonA.opacity(0.2 * intensity)), lineWidth: 1)
        }
    }

    private static func paintAurora(context: GraphicsContext, size: CGSize, time: Double, intensity: Double) {
        let colors = [
            Color(red: 0.55, green: 0.2, blue: 1.0),
            Color(red: 0.9, green: 0.25, blue: 0.7),
            Color(red: 0.3, green: 0.5, blue: 1.0)
        ]
        for n in 0..<4 {
            let color = colors[n % colors.count]
            var ribbon = Path()
            let baseY = size.height * (0.2 + CGFloat(n) * 0.12)
            ribbon.move(to: CGPoint(x: 0, y: baseY))
            var x: CGFloat = 0
            while x <= size.width {
                let y = baseY + sin(Double(x) * 0.015 + time * 0.8 + Double(n)) * 35
                    + cos(Double(x) * 0.008 + time * 0.5) * 18
                ribbon.addLine(to: CGPoint(x: x, y: y))
                x += 6
            }
            // thicken by stroking multiple
            context.stroke(ribbon, with: .color(color.opacity(0.35 * intensity)), lineWidth: 28)
            context.stroke(ribbon, with: .color(color.opacity(0.2 * intensity)), lineWidth: 48)
        }
        // Stars
        for n in 0..<30 {
            let sx = abs(sin(Double(n) * 12.9)) * size.width
            let sy = abs(sin(Double(n) * 78.2)) * size.height * 0.5
            let tw = 0.3 + 0.7 * (0.5 + 0.5 * sin(time * 2 + Double(n)))
            var star = Path()
            star.addEllipse(in: CGRect(x: sx, y: sy, width: 2, height: 2))
            context.fill(star, with: .color(Color.white.opacity(0.5 * intensity * tw)))
        }
    }

    private static func paintOrbit(context: GraphicsContext, size: CGSize, time: Double, accent: Color, intensity: Double) {
        for n in 0..<50 {
            let sx = abs(sin(Double(n) * 12.9)) * size.width
            let sy = abs(sin(Double(n) * 78.2)) * size.height
            let tw = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * (1.1 + Double(n % 5) * 0.3) + Double(n)))
            var star = Path()
            star.addEllipse(in: CGRect(x: sx, y: sy, width: CGFloat(1 + n % 3), height: CGFloat(1 + n % 3)))
            context.fill(star, with: .color(Color.white.opacity(0.55 * intensity * tw)))
        }
        let center = CGPoint(x: size.width * 0.68, y: size.height * 0.32)
        var planet = Path()
        planet.addEllipse(in: CGRect(x: center.x - 36, y: center.y - 36, width: 72, height: 72))
        context.fill(planet, with: .color(accent.opacity(0.55 * intensity)))
        for n in 0..<3 {
            let r = 55 + CGFloat(n) * 28
            var ring = Path()
            ring.addEllipse(in: CGRect(x: center.x - r, y: center.y - r * 0.35, width: r * 2, height: r * 0.7))
            context.stroke(ring, with: .color(accent.opacity((0.35 - Double(n) * 0.08) * intensity)), lineWidth: 1.5)
        }
        // Satellite
        let ang = time * 0.6
        let sat = CGPoint(x: center.x + cos(ang) * 95, y: center.y + sin(ang) * 34)
        var satPath = Path()
        satPath.addEllipse(in: CGRect(x: sat.x - 4, y: sat.y - 4, width: 8, height: 8))
        context.fill(satPath, with: .color(Color.white.opacity(0.8 * intensity)))
    }

    private static func paintHologram(context: GraphicsContext, size: CGSize, time: Double, accent: Color, intensity: Double) {
        let drift = CGFloat(time.truncatingRemainder(dividingBy: 3)) * 8
        // Hex grid
        let step: CGFloat = 36
        var y: CGFloat = -drift
        var row = 0
        while y < size.height + step {
            var x: CGFloat = row % 2 == 0 ? 0 : step * 0.5
            while x < size.width + step {
                var hex = Path()
                let r: CGFloat = 12
                for i in 0..<6 {
                    let a = Double(i) * .pi / 3 - .pi / 6
                    let pt = CGPoint(x: x + r * CGFloat(cos(a)), y: y + r * CGFloat(sin(a)))
                    if i == 0 { hex.move(to: pt) } else { hex.addLine(to: pt) }
                }
                hex.closeSubpath()
                context.stroke(hex, with: .color(accent.opacity(0.18 * intensity)), lineWidth: 0.8)
                x += step
            }
            y += step * 0.86
            row += 1
        }
        // Scanning beam
        let beamY = size.height * (0.5 + 0.4 * sin(time * 0.7))
        var beam = Path()
        beam.addRect(CGRect(x: 0, y: beamY, width: size.width, height: 3))
        context.fill(beam, with: .color(accent.opacity(0.35 * intensity)))
        // HUD brackets
        let inset: CGFloat = 28
        var hud = Path()
        hud.move(to: CGPoint(x: inset, y: inset + 40))
        hud.addLine(to: CGPoint(x: inset, y: inset))
        hud.addLine(to: CGPoint(x: inset + 40, y: inset))
        context.stroke(hud, with: .color(accent.opacity(0.5 * intensity)), lineWidth: 2)
    }

    private static func paintIonStorm(context: GraphicsContext, size: CGSize, time: Double, accent: Color, intensity: Double) {
        for n in 0..<5 {
            let seed = Double(n) * 2.3
            let x0 = size.width * (0.2 + 0.15 * CGFloat(n))
            var bolt = Path()
            bolt.move(to: CGPoint(x: x0, y: 0))
            var y: CGFloat = 0
            var x = x0
            while y < size.height * 0.7 {
                y += 18 + CGFloat(n)
                x += CGFloat(sin(time * 3 + seed + Double(y) * 0.05)) * 22
                bolt.addLine(to: CGPoint(x: x, y: y))
            }
            let flash = 0.25 + 0.35 * max(0, sin(time * 4 + seed))
            context.stroke(bolt, with: .color(Color.white.opacity(flash * intensity)), lineWidth: 2)
            context.stroke(bolt, with: .color(accent.opacity(flash * 0.7 * intensity)), lineWidth: 5)
        }
        for n in 0..<25 {
            let x = abs(sin(Double(n) * 9.1 + time * 0.3)) * size.width
            let y = abs(cos(Double(n) * 4.2 + time * 0.5)) * size.height
            var p = Path()
            p.addEllipse(in: CGRect(x: x, y: y, width: 3, height: 3))
            context.fill(p, with: .color(accent.opacity(0.35 * intensity)))
        }
    }

    // MARK: - Daredevil scenes

    private static func paintDaredevilRooftop(context: GraphicsContext, size: CGSize, time: Double, intensity: Double) {
        let red = Color(red: 0.78, green: 0.09, blue: 0.14)
        // Skyline
        for n in 0..<8 {
            let x = size.width * CGFloat(n) / 8
            let h = size.height * (0.2 + CGFloat((n * 5) % 4) * 0.08)
            var b = Path()
            b.addRect(CGRect(x: x, y: size.height * 0.55 - h * 0.3, width: size.width / 8.5, height: h + size.height * 0.4))
            context.fill(b, with: .color(Color.black.opacity(0.45 * intensity)))
        }
        // Horned mask silhouette (simple)
        let cx = size.width * 0.5
        let cy = size.height * 0.38 + sin(time * 1.2) * 4
        var head = Path()
        head.addEllipse(in: CGRect(x: cx - 40, y: cy - 28, width: 80, height: 70))
        context.fill(head, with: .color(red.opacity(0.55 * intensity)))
        // Horns
        var hornL = Path()
        hornL.move(to: CGPoint(x: cx - 28, y: cy - 18))
        hornL.addLine(to: CGPoint(x: cx - 48, y: cy - 70))
        hornL.addLine(to: CGPoint(x: cx - 10, y: cy - 22))
        context.fill(hornL, with: .color(red.opacity(0.7 * intensity)))
        var hornR = Path()
        hornR.move(to: CGPoint(x: cx + 28, y: cy - 18))
        hornR.addLine(to: CGPoint(x: cx + 48, y: cy - 70))
        hornR.addLine(to: CGPoint(x: cx + 10, y: cy - 22))
        context.fill(hornR, with: .color(red.opacity(0.7 * intensity)))
        // Pulse rings (radar sense)
        let beat = 0.5 + 0.5 * sin(time * 2.4)
        for n in 1...3 {
            let r = CGFloat(40 + n * 28) * (0.85 + 0.15 * beat)
            var ring = Path()
            ring.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            context.stroke(ring, with: .color(red.opacity((0.25 / Double(n)) * intensity)), lineWidth: 1.5)
        }
    }

    private static func paintHellsKitchen(context: GraphicsContext, size: CGSize, time: Double, intensity: Double) {
        let fire = Color(red: 0.95, green: 0.35, blue: 0.08)
        let dark = Color(red: 0.12, green: 0.04, blue: 0.03)
        // Brick blocks
        for row in 0..<10 {
            for col in 0..<6 {
                let x = CGFloat(col) * (size.width / 6) + (row % 2 == 0 ? 0 : size.width / 12)
                let y = size.height * 0.35 + CGFloat(row) * 28
                var brick = Path()
                brick.addRect(CGRect(x: x, y: y, width: size.width / 6 - 3, height: 24))
                context.fill(brick, with: .color(dark.opacity(0.55 * intensity)))
                context.stroke(brick, with: .color(fire.opacity(0.12 * intensity)), lineWidth: 0.5)
            }
        }
        // Fire glow bottom
        for n in 0..<4 {
            let phase = time * (1.5 + Double(n) * 0.2)
            var flame = Path()
            let base = size.width * (0.2 + CGFloat(n) * 0.18)
            flame.move(to: CGPoint(x: base, y: size.height))
            flame.addCurve(
                to: CGPoint(x: base + 30, y: size.height),
                control1: CGPoint(x: base + 5, y: size.height - 80 - CGFloat(sin(phase)) * 30),
                control2: CGPoint(x: base + 25, y: size.height - 60 - CGFloat(cos(phase)) * 20)
            )
            context.fill(flame, with: .color(fire.opacity(0.35 * intensity)))
        }
        // Street lamp
        var lamp = Path()
        lamp.addRect(CGRect(x: size.width * 0.8, y: size.height * 0.25, width: 4, height: size.height * 0.4))
        context.fill(lamp, with: .color(Color.black.opacity(0.5 * intensity)))
        var lampGlow = Path()
        lampGlow.addEllipse(in: CGRect(x: size.width * 0.8 - 22, y: size.height * 0.2, width: 48, height: 48))
        context.fill(lampGlow, with: .color(fire.opacity(0.25 * intensity * (0.7 + 0.3 * sin(time * 5)))))
    }

    private static func paintMurdockRain(context: GraphicsContext, size: CGSize, time: Double, intensity: Double) {
        let red = Color(red: 0.9, green: 0.22, blue: 0.18)
        // Blindfold silhouette
        let cx = size.width * 0.5
        let cy = size.height * 0.36
        var head = Path()
        head.addEllipse(in: CGRect(x: cx - 36, y: cy - 40, width: 72, height: 80))
        context.fill(head, with: .color(Color(red: 0.15, green: 0.1, blue: 0.1).opacity(0.7 * intensity)))
        var band = Path()
        band.addRoundedRect(in: CGRect(x: cx - 40, y: cy - 8, width: 80, height: 16), cornerSize: CGSize(width: 4, height: 4))
        context.fill(band, with: .color(red.opacity(0.75 * intensity)))
        // Rain
        for n in 0..<55 {
            let x = CGFloat((n * 47) % max(Int(size.width), 1))
            let y = CGFloat((Double(n * 31) + time * 180).truncatingRemainder(dividingBy: Double(size.height)))
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x + 3, y: y + 16))
            context.stroke(drop, with: .color(Color.white.opacity(0.18 * intensity)), lineWidth: 1)
        }
        // Red window glow
        var win = Path()
        win.addRect(CGRect(x: size.width * 0.15, y: size.height * 0.55, width: 36, height: 50))
        context.fill(win, with: .color(red.opacity(0.3 * intensity * (0.6 + 0.4 * sin(time)))))
    }

    private static func paintSoftWash(context: GraphicsContext, size: CGSize, time: Double, colors: [Color], intensity: Double) {
        guard let c0 = colors.first else { return }
        for n in 0..<3 {
            let color = colors[n % colors.count]
            let cx = size.width * (0.3 + 0.2 * CGFloat(n) + 0.05 * sin(time * 0.4 + Double(n)))
            let cy = size.height * (0.35 + 0.15 * CGFloat(n))
            let r = min(size.width, size.height) * 0.35
            var p = Path()
            p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            context.fill(p, with: .color(color.opacity(0.2 * intensity)))
        }
        _ = c0
    }
}

extension View {
    /// Lets the living theme atmosphere show through lists / forms / scroll views.
    func themedScreenChrome() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.clear)
    }

    /// Very light wash — atmosphere must remain visible.
    func themedGroupedFill() -> some View {
        self.background {
            Color.clear.ignoresSafeArea()
        }
    }
}
