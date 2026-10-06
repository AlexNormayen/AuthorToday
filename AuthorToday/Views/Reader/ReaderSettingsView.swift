import SwiftUI
import PhotosUI
import UIKit

struct ReaderSettingsView: View {
    @EnvironmentObject private var settings: ReaderSettingsStore
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var photoItem: PhotosPickerItem?
    @State private var showPaywall = false
    @State private var paywallReason: String?

    private var ink: Color {
        appearance.themePreset.backgroundImageName != nil
            ? Color.white
            : appearance.themePreset.chromePrimaryText(colorScheme: colorScheme)
    }

    private var secondaryInk: Color {
        appearance.themePreset.backgroundImageName != nil
            ? Color.white.opacity(0.88)
            : appearance.themePreset.chromeSecondaryText(accent: appearance.accent, colorScheme: colorScheme)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading) {
                    Label("Яркость", systemImage: "lightbulb")
                        .foregroundStyle(ink)
                    Slider(
                        value: Binding(
                            get: { settings.brightnessOverride ?? Double(UIScreen.main.brightness) },
                            set: { settings.brightnessOverride = $0 }
                        ),
                        in: 0.05...1
                    )
                    .tint(appearance.accent)
                }
                .themedPanelRow()
                Text("На странице чтения проведите пальцем вверх/вниз по правому краю — яркость экрана.")
                    .font(.caption)
                    .foregroundStyle(secondaryInk)
                    .themedPanelRow()
                VStack(alignment: .leading) {
                    Label("Размер \(Int(settings.fontSize))", systemImage: "textformat.size")
                        .foregroundStyle(ink)
                    Slider(value: $settings.fontSize, in: 12...36, step: 1)
                        .tint(appearance.accent)
                }
                .themedPanelRow()
                VStack(alignment: .leading) {
                    Label("Поля \(Int(settings.marginHorizontal))", systemImage: "text.alignleft")
                        .foregroundStyle(ink)
                    Slider(value: $settings.marginHorizontal, in: 8...48, step: 1)
                        .tint(appearance.accent)
                }
                .themedPanelRow()
                VStack(alignment: .leading) {
                    Label("Высота строк \(Int(settings.lineSpacing))", systemImage: "arrow.up.and.down.text.horizontal")
                        .foregroundStyle(ink)
                    Slider(value: $settings.lineSpacing, in: 0...24, step: 1)
                        .tint(appearance.accent)
                }
                .themedPanelRow()
            }

            Section {
                ForEach(ReaderFontFamily.allCases) { family in
                    Button {
                        settings.fontFamily = family
                    } label: {
                        HStack {
                            Text(family.title)
                                .font(family.font(size: 17))
                                .foregroundStyle(ink)
                            Spacer()
                            if settings.fontFamily == family {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(appearance.accent)
                            }
                        }
                    }
                    .themedPanelRow()
                }
            } header: {
                Text("Шрифт").themedSectionChrome()
            }

            Section {
                Toggle("Перенос текста", isOn: $settings.textWrap)
                    .foregroundStyle(ink)
                    .tint(appearance.accent)
                    .themedPanelRow()
                Toggle(
                    "Своя цветовая схема",
                    isOn: Binding(
                        get: { settings.useCustomColors },
                        set: { on in
                            if on, !pro.isProUnlocked {
                                paywallReason = "Свой цвет фона читалки доступен в Читальня Pro."
                                showPaywall = true
                                return
                            }
                            settings.useCustomColors = on
                            if on { settings.theme = .customColor }
                        }
                    )
                )
                .foregroundStyle(ink)
                .tint(appearance.accent)
                .themedPanelRow()
                if settings.useCustomColors {
                    ColorPicker("Цвет текста", selection: Binding(
                        get: { Color(hex: settings.customTextHex) ?? .primary },
                        set: {
                            settings.customTextHex = $0.toHex()
                            settings.theme = .customColor
                        }
                    ))
                    .foregroundStyle(ink)
                    .themedPanelRow()
                    ColorPicker("Цвет фона", selection: Binding(
                        get: { Color(hex: settings.customBackgroundHex) ?? .white },
                        set: {
                            settings.customBackgroundHex = $0.toHex()
                            settings.theme = .customColor
                        }
                    ))
                    .foregroundStyle(ink)
                    .themedPanelRow()
                }
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ReaderThemePreset.allCases.filter { $0 != .customImage && $0 != .customColor }) { preset in
                            Button {
                                settings.useCustomColors = false
                                settings.theme = preset
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(preset.defaultBackground)
                                        .frame(width: 56, height: 56)
                                        .overlay {
                                            Text("Аа")
                                                .foregroundStyle(preset.defaultText)
                                        }
                                        .overlay {
                                            if settings.theme == preset && !settings.useCustomColors {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(appearance.accent, lineWidth: 2)
                                            }
                                        }
                                    Text(preset.title)
                                        .font(.caption2)
                                        .foregroundStyle(secondaryInk)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .themedPanelRow()
                let unlocked = pro.isProUnlocked
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(
                        unlocked ? "Свой фон‑картинка" : "Свой фон‑картинка (Pro)",
                        systemImage: unlocked ? "photo" : "lock.fill"
                    )
                    .foregroundStyle(ink)
                }
                .themedPanelRow()
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    if !pro.isProUnlocked {
                        photoItem = nil
                        paywallReason = "Своя картинка фона читалки доступна в Читальня Pro."
                        showPaywall = true
                        return
                    }
                    Task { await settings.setCustomBackground(from: item) }
                }
            } header: {
                Text("Пресеты фона").themedSectionChrome()
            }

            Section {
                Picker("Режим", selection: $settings.pageTurnMode) {
                    ForEach(PageTurnMode.allCases) { mode in
                        HStack {
                            Text(mode.title)
                            if ProFeatures.requiresPro(mode), !pro.isProUnlocked {
                                Text("Pro")
                                    .font(.caption2)
                                    .foregroundStyle(secondaryInk)
                            }
                        }
                        .tag(mode)
                    }
                }
                .foregroundStyle(ink)
                .tint(ink)
                .themedPanelRow()
                .onChange(of: settings.pageTurnMode) { _, newValue in
                    if ProFeatures.requiresPro(newValue), !pro.isProUnlocked {
                        settings.pageTurnMode = .verticalScroll
                        paywallReason = "Режим «Перелистывание» доступен в Читальня Pro."
                        showPaywall = true
                    }
                }
            } header: {
                Text("Перелистывание").themedSectionChrome()
            }

            Section {
                Toggle("Не гасить экран", isOn: $settings.keepScreenOn)
                    .foregroundStyle(ink)
                    .tint(appearance.accent)
                    .themedPanelRow()
            }

            Section {
                Text("В ту ночь дождь шёл не переставая, а фонарь у калитки качал жёлтый круг по мокрой брусчатке.")
                    .font(settings.fontFamily.font(size: settings.fontSize))
                    .foregroundStyle(settings.textColor)
                    .lineSpacing(settings.lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(settings.solidBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .themedPanelRow()
            } header: {
                Text("Превью").themedSectionChrome()
            }
        }
        .themedAtmosphereList()
        .environment(\.themePreset, appearance.themePreset)
        .environment(\.themeAccent, appearance.accent)
        .preferredColorScheme(appearance.preferredColorScheme)
        .tint(ink)
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreenChrome()
        .background {
            ThemeAtmosphereView(preset: appearance.themePreset)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: settings.brightnessOverride) { _, value in
            if let value {
                UIScreen.main.brightness = value
            }
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView(reason: paywallReason)
                .environmentObject(pro)
                .environmentObject(appearance)
                .environmentObject(OfflineStore.shared)
        }
    }
}
