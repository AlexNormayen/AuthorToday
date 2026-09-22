import SwiftUI
import UIKit

/// Vertical drag on the right edge adjusts screen brightness (up = brighter, down = dimmer).
struct ReaderBrightnessEdgeOverlay: ViewModifier {
    @EnvironmentObject private var settings: ReaderSettingsStore

    @State private var baseBrightness: Double = Double(UIScreen.main.brightness)
    @State private var hudValue: Double?
    @State private var hudHideTask: Task<Void, Never>?

    private let edgeWidth: CGFloat = 36

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                Color.clear
                    .frame(width: edgeWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 6, coordinateSpace: .local)
                            .onChanged { value in
                                if hudValue == nil {
                                    baseBrightness = settings.brightnessOverride
                                        ?? Double(UIScreen.main.brightness)
                                }
                                // Up → brighter, down → dimmer.
                                let delta = -Double(value.translation.height) / 280.0
                                let next = min(max(baseBrightness + delta, 0.05), 1)
                                applyBrightness(next)
                                hudValue = next
                                scheduleHUDHide()
                            }
                            .onEnded { _ in
                                baseBrightness = settings.brightnessOverride
                                    ?? Double(UIScreen.main.brightness)
                                scheduleHUDHide()
                            }
                    )
                    .accessibilityLabel("Яркость")
                    .accessibilityHint("Проведите вверх или вниз по правому краю, чтобы изменить яркость")
            }
            .overlay {
                if let hudValue {
                    VStack(spacing: 10) {
                        Image(systemName: hudValue < 0.15
                              ? "sun.min.fill"
                              : (hudValue > 0.85 ? "sun.max.fill" : "sun.max"))
                            .font(.title2)
                        ProgressView(value: hudValue)
                            .tint(.white)
                            .frame(width: 120)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.primary)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.15), value: hudValue != nil)
            .onAppear {
                if let value = settings.brightnessOverride {
                    UIScreen.main.brightness = value
                }
            }
    }

    private func applyBrightness(_ value: Double) {
        settings.brightnessOverride = value
        UIScreen.main.brightness = value
    }

    private func scheduleHUDHide() {
        hudHideTask?.cancel()
        hudHideTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            hudValue = nil
        }
    }
}

extension View {
    func readerBrightnessEdgeGesture() -> some View {
        modifier(ReaderBrightnessEdgeOverlay())
    }
}
