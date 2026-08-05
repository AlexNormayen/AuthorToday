import SwiftUI
import PhotosUI
import UIKit

struct ReaderSettingsView: View {
    @EnvironmentObject private var settings: ReaderSettingsStore
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Label("Яркость", systemImage: "lightbulb")
                    Slider(
                        value: Binding(
                            get: { settings.brightnessOverride ?? Double(UIScreen.main.brightness) },
                            set: { settings.brightnessOverride = $0 }
                        ),
                        in: 0.05...1
                    )
                }
                VStack(alignment: .leading) {
                    Label("Размер \(Int(settings.fontSize))", systemImage: "textformat.size")
                    Slider(value: $settings.fontSize, in: 12...36, step: 1)
                }
                VStack(alignment: .leading) {
                    Label("Поля \(Int(settings.marginHorizontal))", systemImage: "text.alignleft")
                    Slider(value: $settings.marginHorizontal, in: 8...48, step: 1)
                }
                VStack(alignment: .leading) {
                    Label("Высота строк \(Int(settings.lineSpacing))", systemImage: "arrow.up.and.down.text.horizontal")
                    Slider(value: $settings.lineSpacing, in: 0...24, step: 1)
                }
            }

            Section("Шрифт") {
                ForEach(ReaderFontFamily.allCases) { family in
                    Button {
                        settings.fontFamily = family
                    } label: {
                        HStack {
                            Text(family.title)
                                .font(family.font(size: 17))
                                .foregroundStyle(.primary)
                            Spacer()
                            if settings.fontFamily == family {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }

            Section {
                Toggle("Перенос текста", isOn: $settings.textWrap)
                Toggle("Своя цветовая схема", isOn: $settings.useCustomColors)
                if settings.useCustomColors {
                    ColorPicker("Цвет текста", selection: Binding(
                        get: { Color(hex: settings.customTextHex) ?? .primary },
                        set: {
                            settings.customTextHex = $0.toHex()
                            settings.theme = .customColor
                        }
                    ))
                    ColorPicker("Цвет фона", selection: Binding(
                        get: { Color(hex: settings.customBackgroundHex) ?? .white },
                        set: {
                            settings.customBackgroundHex = $0.toHex()
                            settings.theme = .customColor
                        }
                    ))
                }
            }

            Section("Пресеты фона") {
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
                                                    .stroke(Color.accentColor, lineWidth: 2)
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
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Свой фон‑картинка", systemImage: "photo")
                }
                .onChange(of: photoItem) { _, item in
                    Task { await settings.setCustomBackground(from: item) }
                }
            }

            Section("Перелистывание") {
                Picker("Режим", selection: $settings.pageTurnMode) {
                    ForEach(PageTurnMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section {
                Toggle("Не гасить экран", isOn: $settings.keepScreenOn)
            }

            Section("Превью") {
                Text("В ту ночь дождь шёл не переставая, а фонарь у калитки качал жёлтый круг по мокрой брусчатке.")
                    .font(settings.fontFamily.font(size: settings.fontSize))
                    .foregroundStyle(settings.textColor)
                    .lineSpacing(settings.lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(settings.solidBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.brightnessOverride) { _, value in
            if let value {
                UIScreen.main.brightness = value
            }
        }
    }
}
