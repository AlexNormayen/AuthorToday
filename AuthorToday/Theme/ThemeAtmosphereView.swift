import SwiftUI
import UIKit

/// Full-screen living theme backdrop using real background images.
/// Uses a slow autoreversing animation (not TimelineView) so taps stay responsive.
struct ThemeAtmosphereView: View {
    let preset: AppThemePreset
    var intensity: Double = 1
    var animated: Bool = true

    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                preset.atmosphereBase

                if let name = preset.backgroundImageName, UIImage(named: name) != nil {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: geo.size.width * 1.14,
                            height: geo.size.height * 1.14
                        )
                        .scaleEffect(animated && drift ? 1.12 : 1.07)
                        .offset(
                            x: animated && drift ? geo.size.width * 0.028 : -geo.size.width * 0.02,
                            y: animated && drift ? -geo.size.height * 0.018 : geo.size.height * 0.014
                        )
                        .opacity(intensity)
                } else {
                    LinearGradient(
                        colors: [preset.accent.opacity(0.35), preset.atmosphereBase],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

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
        .onAppear { startDriftIfNeeded() }
        .onChange(of: animated) { _, _ in startDriftIfNeeded() }
        .onChange(of: preset) { _, _ in
            drift = false
            startDriftIfNeeded()
        }
    }

    private func startDriftIfNeeded() {
        guard animated else {
            drift = false
            return
        }
        // Delay so the first frame is static and the first tap isn't fighting layout.
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
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

    /// Reliable tap target for plain buttons (esp. inside ScrollView).
    func tappableRow() -> some View {
        self
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
    }
}
