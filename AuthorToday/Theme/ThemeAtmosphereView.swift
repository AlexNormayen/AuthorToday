import SwiftUI
import UIKit

/// Full-screen living theme backdrop using real background images.
/// Photo themes stay sharp; list screens get a soft dark scrim (Option A) for readable chrome.
struct ThemeAtmosphereView: View {
    let preset: AppThemePreset
    var intensity: Double = 1
    var animated: Bool = true
    /// Soft black wash over photos so lists/settings read without plates (off in theme previews).
    var showsContentScrim: Bool = true

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

                    if showsContentScrim, preset.contentScrimOpacity > 0.001 {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(preset.contentScrimOpacity * 0.88 * intensity),
                                Color.black.opacity(preset.contentScrimOpacity * intensity),
                                Color.black.opacity(min(preset.contentScrimOpacity * 1.08, 0.62) * intensity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
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

/// Soft inset plate — kept for rare callers; chrome UI no longer uses plates by default.
struct ThemedPanelBackground: View {
    var cornerRadius: CGFloat = 12
    var elevated: Bool = false

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
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
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(preset.chromeSecondaryText(accent: accent))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Soft lift only — readability comes from the content scrim, not outlines/plates.
    func themedReadableText() -> some View {
        modifier(ThemedReadableTextModifier())
    }

    /// Footnotes / captions with accent-derived color (no outline ring).
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

    /// Transparent row — no plate, no divider.
    func themedListRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// List / form rows: clear, no plates, no separators (Option A spacing-only).
    func themedPanelRow(cornerRadius: CGFloat = 12) -> some View {
        _ = cornerRadius
        return self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    /// Empty states without floating cards.
    func themedEmptyStateCard() -> some View {
        modifier(ThemedEmptyStateModifier())
    }

    /// Reliable tap target for plain buttons (esp. inside ScrollView).
    func tappableRow() -> some View {
        self
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
    }

    /// Sort / menu label — no capsule plate.
    func themedChromeChip() -> some View {
        modifier(ThemedChromeChipModifier())
    }

    /// Section headers / footers: soft accent text, no plate or outline.
    func themedSectionChrome() -> some View {
        modifier(ThemedSectionChromeModifier())
    }
}

private struct ThemedReadableTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.28), radius: 1.5, x: 0, y: 0.5)
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
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .themedReadableText()
    }
}

private struct ThemedSectionChromeModifier: ViewModifier {
    @Environment(\.themePreset) private var preset
    @Environment(\.themeAccent) private var accent

    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .foregroundStyle(preset.chromePrimaryText.opacity(0.92))
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .themedReadableText()
    }
}
