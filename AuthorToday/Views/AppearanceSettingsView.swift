import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var readerSettings: ReaderSettingsStore
    @EnvironmentObject private var pro: ProEntitlementStore

    @State private var showPaywall = false
    @State private var paywallReason: String?

    var body: some View {
        Form {
            Section {
                ZStack {
                    ThemeAtmosphereView(preset: appearance.themePreset, intensity: 1, animated: true)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(spacing: 8) {
                        Text(appearance.themePreset.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Живой фон темы")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(20)
                    .background(.ultraThinMaterial.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .frame(height: 140)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section("Тема приложения") {
                Picker("Режим", selection: $appearance.colorMode) {
                    ForEach(AppColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AppThemePreset.allCases) { preset in
                            let locked = ProFeatures.requiresPro(preset) && !pro.isProUnlocked
                            Button {
                                if locked {
                                    paywallReason = "Тема «\(preset.title)» доступна в Читальня Pro."
                                    showPaywall = true
                                    return
                                }
                                appearance.themePreset = preset
                                if preset.prefersDark {
                                    appearance.colorMode = .dark
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        ThemeAtmosphereView(
                                            preset: preset,
                                            intensity: 0.9,
                                            animated: false
                                        )
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(
                                                    appearance.themePreset == preset
                                                        ? preset.accent
                                                        : Color.white.opacity(0.15),
                                                    lineWidth: appearance.themePreset == preset ? 2.5 : 1
                                                )
                                        }
                                        .opacity(locked ? 0.55 : 1)

                                        Circle()
                                            .fill(preset == .custom
                                                  ? (Color(hex: appearance.customAccentHex) ?? preset.accent)
                                                  : preset.accent)
                                            .frame(width: 14, height: 14)
                                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                                            .offset(x: 16, y: 16)

                                        if locked {
                                            Image(systemName: "lock.fill")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .padding(6)
                                                .background(.black.opacity(0.45), in: Circle())
                                        }
                                    }
                                    .frame(width: 56, height: 56)
                                    .contentShape(Rectangle())

                                    Text(preset.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 72)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if appearance.themePreset == .custom {
                    ColorPicker(
                        "Свой акцент",
                        selection: Binding(
                            get: { Color(hex: appearance.customAccentHex) ?? .green },
                            set: { appearance.customAccentHex = $0.toHex() }
                        )
                    )
                }
            }

            Section("Читалка") {
                NavigationLink("Шрифт, фон, отступы") {
                    ReaderSettingsView()
                }
                Picker("Перелистывание", selection: $readerSettings.pageTurnMode) {
                    ForEach(PageTurnMode.allCases) { mode in
                        HStack {
                            Text(mode.title)
                            if ProFeatures.requiresPro(mode) {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(mode)
                    }
                }
                .onChange(of: readerSettings.pageTurnMode) { _, newValue in
                    if ProFeatures.requiresPro(newValue), !pro.isProUnlocked {
                        readerSettings.pageTurnMode = .verticalScroll
                        paywallReason = "Режим «Перелистывание» доступен в Читальня Pro."
                        showPaywall = true
                    }
                }
            }

            Section {
                Text("Бесплатно: спокойные темы Бумага / Облако / Камень и Author.Today (без фото-фона, удобнее читать списки), плюс Мох, Океан, Вино, Графит, Песок. Futuristic, фото-темы и свой цвет — в Pro. Тема задаёт фон и акцент; фон читалки настраивается отдельно.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreenChrome()
        .background {
            ThemeAtmosphereView(preset: appearance.themePreset)
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .sheet(isPresented: $showPaywall) {
            ProPaywallView(reason: paywallReason)
                .environmentObject(pro)
                .environmentObject(appearance)
                .environmentObject(OfflineStore.shared)
        }
    }
}
