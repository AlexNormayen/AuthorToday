import SwiftUI
import UIKit

/// Full-screen living theme backdrop using real background images.
/// Photo themes stay sharp; list screens get a soft scrim (Option A) for readable chrome.
struct ThemeAtmosphereView: View {
    let preset: AppThemePreset
    var intensity: Double = 1
    var animated: Bool = true
    /// Soft wash over photos so lists/settings read without plates (off in theme previews).
    var showsContentScrim: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                baseFill

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
                        let useDarkScrim = colorScheme == .dark
                        let ink = useDarkScrim ? Color.black : Color.white
                        let strength = useDarkScrim
                            ? preset.contentScrimOpacity
                            : min(preset.contentScrimOpacity + 0.12, 0.62)
                        LinearGradient(
                            colors: [
                                ink.opacity(strength * 0.88 * intensity),
                                ink.opacity(strength * intensity),
                                ink.opacity(min(strength * 1.08, 0.70) * intensity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
                } else {
                    LinearGradient(
                        colors: [
                            preset.accent.opacity(preset.atmosphereAccentWash * intensity * (colorScheme == .dark ? 0.55 : 1)),
                            baseFill
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    if colorScheme == .dark {
                        Color.black.opacity(0.42 * intensity)
                            .allowsHitTesting(false)
                    } else {
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

    private var baseFill: Color {
        if colorScheme == .dark, preset.backgroundImageName == nil {
            return preset.mistDark
        }
        return preset.atmosphereBase
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(preset.chromeSecondaryText(accent: accent, colorScheme: colorScheme))
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(preset.chromePrimaryText(colorScheme: colorScheme))
                .multilineTextAlignment(.center)
            if let description, !description.isEmpty {
                Text(description)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(preset.chromeSecondaryText(accent: accent, colorScheme: colorScheme))
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(preset.chromePrimaryText(colorScheme: colorScheme))
                    .multilineTextAlignment(.center)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(preset.chromeSecondaryText(accent: accent, colorScheme: colorScheme))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Section footnote: full text at primary brightness, red * marks it as explanation.
struct ThemedFooterNote: View {
    var text: String

    @Environment(\.themePreset) private var preset
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("*")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(red: 0.92, green: 0.22, blue: 0.24))
            Text(text)
                .font(.subheadline.weight(.regular))
                .foregroundStyle(preset.chromePrimaryText(colorScheme: colorScheme))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedReadableText()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Пояснение. \(text)")
    }
}

extension View {
    /// Soft lift only — readability comes from the content scrim, not outlines/plates.
    func themedReadableText() -> some View {
        modifier(ThemedReadableTextModifier())
    }

    /// Footnotes / captions — contrast follows Light/Dark, not only the preset default.
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

    /// Section headers: follow active color scheme.
    func themedSectionChrome() -> some View {
        modifier(ThemedSectionChromeModifier())
    }

    /// Full footer copy at primary list brightness (no plate / no dim secondary).
    func themedFooterNote() -> some View {
        modifier(ThemedFooterNoteModifier())
    }
}

private struct ThemedReadableTextModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.35),
                radius: 1.2,
                x: 0,
                y: 0.5
            )
    }
}

private struct ThemedSecondaryTextModifier: ViewModifier {
    @Environment(\.themePreset) private var preset
    @Environment(\.themeAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(preset.chromeSecondaryText(accent: accent, colorScheme: colorScheme))
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
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(preset.chromeSecondaryText(accent: accent, colorScheme: colorScheme))
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .themedReadableText()
    }
}

private struct ThemedSectionChromeModifier: ViewModifier {
    @Environment(\.themePreset) private var preset
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .foregroundStyle(preset.chromePrimaryText(colorScheme: colorScheme).opacity(0.92))
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .themedReadableText()
    }
}

private struct ThemedFooterNoteModifier: ViewModifier {
    @Environment(\.themePreset) private var preset
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("*")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(red: 0.92, green: 0.22, blue: 0.24))
            content
                .font(.subheadline.weight(.regular))
                .foregroundStyle(preset.chromePrimaryText(colorScheme: colorScheme))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedReadableText()
        .accessibilityLabel("Пояснение")
    }
}
