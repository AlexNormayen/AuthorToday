import SwiftUI
import UIKit

/// Full-screen living theme backdrop using real background images.
struct ThemeAtmosphereView: View {
    let preset: AppThemePreset
    var intensity: Double = 1
    var animated: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                preset.atmosphereBase

                if let name = preset.backgroundImageName, UIImage(named: name) != nil {
                    TimelineView(.animation(minimumInterval: animated ? 1.0 / 30.0 : 3600, paused: !animated)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let scale = 1.08 + 0.04 * sin(t * 0.12)
                        let dx = geo.size.width * 0.03 * sin(t * 0.08)
                        let dy = geo.size.height * 0.02 * cos(t * 0.1)
                        Image(name)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width * scale, height: geo.size.height * scale)
                            .offset(x: dx, y: dy)
                            .opacity(intensity)
                    }
                } else {
                    // Fallback wash if asset missing
                    LinearGradient(
                        colors: [preset.accent.opacity(0.35), preset.atmosphereBase],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                // Readability scrim so lists stay legible over busy photos.
                LinearGradient(
                    colors: [
                        Color.black.opacity(preset.prefersDark ? 0.35 * intensity : 0.12 * intensity),
                        Color.black.opacity(preset.prefersDark ? 0.55 * intensity : 0.22 * intensity)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
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

extension View {
    /// Lets the living theme atmosphere show through lists / forms / scroll views.
    func themedScreenChrome() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.clear)
    }

    /// Transparent fill so photo theme shows through.
    func themedGroupedFill() -> some View {
        self.background {
            Color.clear.ignoresSafeArea()
        }
    }

    /// Soft card behind a list row for readability on photo backgrounds.
    func themedListRow() -> some View {
        self.listRowBackground(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.92))
                .padding(.vertical, 2)
        )
    }
}
