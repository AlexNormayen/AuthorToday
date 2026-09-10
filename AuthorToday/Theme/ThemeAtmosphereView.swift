import SwiftUI
import UIKit

/// Full-screen living theme backdrop using real background images.
/// Photo themes stay sharp and bright — no blur / heavy frost wash.
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
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(animated && drift ? 1.04 : 1.0)
                        .offset(
                            x: animated && drift ? geo.size.width * 0.012 : 0,
                            y: animated && drift ? -geo.size.height * 0.008 : 0
                        )
                        .opacity(intensity)
                } else {
                    LinearGradient(
                        colors: [
                            preset.accent.opacity(preset.atmosphereAccentWash * intensity),
                            preset.atmosphereBase
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    let top = preset.atmosphereOverlayTop * intensity
                    let bottom = preset.atmosphereOverlayBottom * intensity
                    if top > 0.001 || bottom > 0.001 {
                        let ink = preset.atmosphereUsesLightScrim ? Color.white : Color.black
                        LinearGradient(
                            colors: [ink.opacity(top), ink.opacity(bottom)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
                }
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
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
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

/// Centered loading placeholder that doesn't collapse into a tiny themed scrap.
struct LoadingStateView: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.primary)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .themedReadableText()
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .themedReadableText()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Soft shadow so labels stay readable on busy photo themes (no frosted card).
    func themedReadableText() -> some View {
        self
            .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
            .shadow(color: .white.opacity(0.35), radius: 1, x: 0, y: 0)
    }

    /// Lets the living theme atmosphere show through lists / forms / scroll views.
    func themedScreenChrome() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.clear)
    }

    /// No wash over the photo — content sits on the atmosphere.
    func themedGroupedFill() -> some View {
        self.background {
            Color.clear.ignoresSafeArea()
        }
    }

    /// Transparent row — no white plate, no border.
    func themedListRow() -> some View {
        self.listRowBackground(Color.clear)
    }

    /// Form / inset rows without white cards or outlines.
    func themedPanelRow(cornerRadius: CGFloat = 14) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Color.primary.opacity(0.18))
    }

    /// Empty states without a white floating window.
    func themedEmptyStateCard() -> some View {
        self
            .padding(22)
            .frame(maxWidth: 360)
            .themedReadableText()
            .padding(.horizontal, 20)
    }

    /// Reliable tap target for plain buttons (esp. inside ScrollView).
    func tappableRow() -> some View {
        self
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
    }
}
