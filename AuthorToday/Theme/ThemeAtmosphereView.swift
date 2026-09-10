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

private struct ThemeAccentKey: EnvironmentKey {
    static let defaultValue: Color = Color(red: 0.18, green: 0.42, blue: 0.36)
}

extension EnvironmentValues {
    var themePreset: AppThemePreset {
        get { self[ThemePresetKey.self] }
        set { self[ThemePresetKey.self] = newValue }
    }

    var themeAccent: Color {
        get { self[ThemeAccentKey.self] }
        set { self[ThemeAccentKey.self] = newValue }
    }
}

/// Soft inset plate matching the active theme — accent wash + border + depth.
struct ThemedPanelBackground: View {
    var cornerRadius: CGFloat = 12
    /// Stronger shadow for floating cards (empty states); softer for list rows.
    var elevated: Bool = false
    @Environment(\.themePreset) private var preset
    @Environment(\.themeAccent) private var accent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: [
                        preset.chromePanelFill,
                        preset.chromePanelFill.opacity(0.92),
                        accent.opacity(preset.chromeInk == .onDark ? 0.28 : 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            preset.chromePanelBorder(accent: accent),
                            accent.opacity(preset.chromeInk == .onDark ? 0.18 : 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: elevated ? 1.2 : 1
                )
            }
            .shadow(
                color: preset.chromePanelShadow(accent: accent),
                radius: elevated ? 14 : 5,
                x: 0,
                y: elevated ? 6 : 2
            )
            .shadow(
                color: accent.opacity(preset.chromeInk == .onDark ? 0.22 : 0.12),
                radius: elevated ? 6 : 2,
                x: 0,
                y: 1
            )
    }
}

/// Empty / unavailable state without system white `ContentUnavailableView` cards.
struct ThemedEmptyStateView: View {
    let title: String
    let systemImage: String
    var description: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.themePreset) private var preset
    @Environment(\.themeAccent) private var accent

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(preset.chromeSecondaryText(accent: accent))
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(preset.chromePrimaryText)
                .multilineTextAlignment(.center)
            if let description, !description.isEmpty {
                Text(description)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(preset.chromeSecondaryText(accent: accent))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .padding(.top, 4)
            }
        }
        .padding(22)
        .frame(maxWidth: 360)
        .background { ThemedPanelBackground(cornerRadius: 18, elevated: true) }
        .themedReadableText()
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Centered loading placeholder that doesn't collapse into a tiny themed scrap.
struct LoadingStateView: View {
    let title: String
    var subtitle: String? = nil

    @Environment(\.themePreset) private var preset
    @Environment(\.themeAccent) private var accent

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(preset.chromePrimaryText)
                    .multilineTextAlignment(.center)
                    .themedReadableText()
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(preset.chromeSecondaryText(accent: accent))
                        .multilineTextAlignment(.center)
                        .themedReadableText()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background {
                ThemedPanelBackground(cornerRadius: 18, elevated: true)
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

    /// Footnotes / captions with accent-derived contrast (not system gray).
    func themedSecondaryText() -> some View {
        modifier(ThemedSecondaryTextModifier())
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

    /// Form / inset rows with theme-tinted volumetric plates.
    func themedPanelRow(cornerRadius: CGFloat = 12) -> some View {
        self
            .listRowBackground(
                ThemedPanelBackground(cornerRadius: cornerRadius, elevated: false)
                    .padding(.vertical, 2)
            )
            .listRowSeparatorTint(Color.primary.opacity(0.18))
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

    /// Section headers / footers that sit on the photo, not inside list rows.
    func themedSectionChrome() -> some View {
        modifier(ThemedSectionChromeModifier())
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

private struct ThemedSecondaryTextModifier: ViewModifier {
    @Environment(\.themePreset) private var preset
    @Environment(\.themeAccent) private var accent

    func body(content: Content) -> some View {
        content
            .foregroundStyle(preset.chromeSecondaryText(accent: accent))
            .themedReadableText()
    }
}

private struct ThemedEmptyStateModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(22)
            .frame(maxWidth: 360)
            .background {
                ThemedPanelBackground(cornerRadius: 18, elevated: true)
            }
            .themedReadableText()
            .padding(.horizontal, 20)
    }
}

private struct ThemedChromeChipModifier: ViewModifier {
    @Environment(\.themePreset) private var preset
    @Environment(\.themeAccent) private var accent

    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(preset.chromeSecondaryText(accent: accent))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                preset.chromePanelFill,
                                accent.opacity(preset.chromeInk == .onDark ? 0.35 : 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(preset.chromePanelBorder(accent: accent), lineWidth: 1)
                    }
                    .shadow(color: preset.chromePanelShadow(accent: accent), radius: 4, y: 2)
            }
            .themedReadableText()
    }
}

private struct ThemedSectionChromeModifier: ViewModifier {
    @Environment(\.themePreset) private var preset
    @Environment(\.themeAccent) private var accent

    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .foregroundStyle(preset.chromeSecondaryText(accent: accent))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if preset.needsContrastChrome {
                    ThemedPanelBackground(cornerRadius: 10, elevated: false)
                }
            }
    }
}
