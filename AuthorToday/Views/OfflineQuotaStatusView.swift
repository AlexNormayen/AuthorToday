import SwiftUI

/// Free-tier full-download quota: used N / limit.
struct OfflineQuotaStatusView: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var appearance: AppAppearanceStore

    var compact: Bool = false
    var onUpgrade: (() -> Void)? = nil

    private var used: Int { offline.fullyDownloadedCount }
    private var limit: Int { ProFeatures.freeFullDownloadLimit }
    private var exhausted: Bool { !pro.isProUnlocked && used >= limit }
    private var fraction: Double {
        guard limit > 0 else { return 0 }
        return min(Double(used) / Double(limit), 1)
    }

    var body: some View {
        if pro.isProUnlocked {
            if !compact {
                Label("Офлайн без лимита (Pro)", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(appearance.accent)
                    .themedReadableText()
            }
        } else {
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                HStack {
                    Text("Скачано целиком")
                        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(appearance.themePreset.chromePrimaryText)
                        .themedReadableText()
                    Spacer()
                    Text("\(used)/\(limit)")
                        .font(compact ? .caption.monospacedDigit().weight(.bold) : .subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(exhausted ? AppTheme.danger : appearance.accent)
                        .themedReadableText()
                }
                ProgressView(value: fraction)
                    .tint(exhausted ? AppTheme.danger : appearance.accent)
                Text("Открытые главы кэшируются без лимита. Pro снимает потолок на «скачать все».")
                    .font(.caption.weight(.medium))
                    .themedSecondaryText()
                if exhausted, let onUpgrade {
                    Button("Открыть Pro") { onUpgrade() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(appearance.accent)
                }
            }
            .padding(compact ? 4 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.themePreset, appearance.themePreset)
            .environment(\.themeAccent, appearance.accent)
        }
    }
}
