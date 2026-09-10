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
                        colors: [
                            preset.accent.opacity(preset.atmosphereAccentWash * intensity),
                            preset.atmosphereBase
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                LinearGradient(
                    colors: {
                        let ink = preset.atmosphereUsesLightScrim ? Color.white : Color.black
                        return [
                            ink.opacity(preset.atmosphereOverlayTop * intensity),
                            ink.opacity(preset.atmosphereOverlayBottom * intensity)
                        ]
                    }(),
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

/// Centered loading placeholder that doesn't collapse into a tiny themed scrap
/// (bare `ProgressView("…")` can render broken page-style chrome on photo themes).
struct LoadingStateView: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        ZStack {
            // Opaque enough that photo themes don't show through as a tiny scrap.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.primary)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Lets the living theme atmosphere show through lists / forms / scroll views.
    func themedScreenChrome() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.clear)
    }

    /// Soft material fill so photo themes stay visible but body text stays readable.
    func themedGroupedFill() -> some View {
        self.background {
            Rectangle()
                .fill(.regularMaterial)
                .opacity(0.78)
                .ignoresSafeArea()
        }
    }

    /// Soft card behind a list row for readability on photo backgrounds.
    func themedListRow() -> some View {
        self.listRowBackground(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .padding(.vertical, 2)
        )
    }

    /// Frosted panel for Form / inset sections (replaces stark solid white cards).
    func themedPanelRow(cornerRadius: CGFloat = 14) -> some View {
        self.listRowBackground(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
                .padding(.vertical, 1)
        )
    }

    /// Empty / unavailable states stay readable on bright photo themes.
    func themedEmptyStateCard() -> some View {
        self
            .padding(22)
            .frame(maxWidth: 360)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
            }
            .padding(.horizontal, 20)
    }

    /// Reliable tap target for plain buttons (esp. inside ScrollView).
    func tappableRow() -> some View {
        self
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
    }
}
