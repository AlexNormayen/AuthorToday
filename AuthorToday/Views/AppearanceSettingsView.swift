import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var readerSettings: ReaderSettingsStore

    var body: some View {
        Form {
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
                            Button {
                                appearance.themePreset = preset
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(preset == .custom
                                              ? (Color(hex: appearance.customAccentHex) ?? preset.accent)
                                              : preset.accent)
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            if appearance.themePreset == preset {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                    Text(preset.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
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
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section {
                Text("Тёмная тема влияет на весь интерфейс. Фон читалки настраивается отдельно (в том числе ночной пресет и своя картинка).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
    }
}
