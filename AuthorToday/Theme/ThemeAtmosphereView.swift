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

private struct ThemePresetKey: EnvironmentKey {
    static let defaultValue: AppThemePreset = .sand
}

extension EnvironmentValues {
    var themePreset: AppThemePreset {
        get { self[ThemePresetKey.self] }
        set { self[ThemePresetKey.self] = newValue }
    }
}

/// Soft inset plate matching the active theme (never system white).
struct ThemedPanelBackground: View {
    var cornerRadius: CGFloat = 12
    @Environment(\.themePreset) private var preset

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(preset.chromePanelFill)
    }
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
            .background {
                ThemedPanelBackground(cornerRadius: 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Soft halo so labels stay readable on busy photo themes (ink-aware).
    func themedReadableText() -> some View {
        modifier(ThemedReadableTextModifier())
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

    /// Form / inset rows with theme-tinted plates (not system white).
    func themedPanelRow(cornerRadius: CGFloat = 12) -> some View {
        self
            .listRowBackground(ThemedPanelBackground(cornerRadius: cornerRadius))
            .listRowSeparatorTint(Color.primary.opacity(0.22))
    }

    /// Empty states: soft plate + readable text on photo themes.
    func themedEmptyStateCard() -> some View {
        modifier(ThemedEmptyStateModifier())
    }

    /// Reliable tap target for plain buttons (esp. inside ScrollView).
    func tappableRow() -> some View {
        self
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
    }

    /// Capsule chip for menus / sort labels over photo backdrops.
    func themedChromeChip() -> some View {
        modifier(ThemedChromeChipModifier())
    }
}

private struct ThemedReadableTextModifier: ViewModifier {
    @Environment(\.themePreset) private var preset

    func body(content: Content) -> some View {
        let shadow = preset.readableTextShadow
        content
            .shadow(color: shadow.0, radius: shadow.1, x: 0, y: preset.chromeInk == .onDark ? 1 : 0)
            .shadow(
                color: preset.chromeInk == .onLight
                    ? Color.black.opacity(0.12)
                    : Color.black.opacity(0.22),
                radius: preset.chromeInk == .onLight ? 1 : 8,
                x: 0,
                y: preset.chromeInk == .onLight ? 0.5 : 0
            )
    }
}

private struct ThemedEmptyStateModifier: ViewModifier {
    @Environment(\.themePreset) private var preset

    func body(content: Content) -> some View {
        content
            .padding(22)
            .frame(maxWidth: 360)
            .background {
                if preset.needsContrastChrome {
                    ThemedPanelBackground(cornerRadius: 18)
                }
            }
            .themedReadableText()
            .padding(.horizontal, 20)
    }
}

private struct ThemedChromeChipModifier: ViewModifier {
    @Environment(\.themePreset) private var preset

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(preset.chromePanelFill))
            .themedReadableText()
    }
}
