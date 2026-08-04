import SwiftUI
import PhotosUI

struct ReaderSettingsView: View {
    @EnvironmentObject private var settings: ReaderSettingsStore
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section("Шрифт") {
                Picker("Семейство", selection: $settings.fontFamily) {
                    ForEach(ReaderFontFamily.allCases) { family in
                        Text(family.title).tag(family)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Размер \(Int(settings.fontSize))")
                    Slider(value: $settings.fontSize, in: 14...32, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Межстрочный \(Int(settings.lineSpacing))")
                    Slider(value: $settings.lineSpacing, in: 2...20, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Абзацы \(Int(settings.paragraphSpacing))")
                    Slider(value: $settings.paragraphSpacing, in: 4...28, step: 1)
                }
            }

            Section("Отступы") {
                VStack(alignment: .leading) {
                    Text("По горизонтали \(Int(settings.marginHorizontal))")
                    Slider(value: $settings.marginHorizontal, in: 8...40, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("По вертикали \(Int(settings.marginVertical))")
                    Slider(value: $settings.marginVertical, in: 4...36, step: 1)
                }
            }

            Section("Перелистывание") {
                ForEach(PageTurnMode.allCases) { mode in
                    Button {
                        settings.pageTurnMode = mode
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .foregroundStyle(.primary)
                                Text(mode.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.pageTurnMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.moss)
                            }
                        }
                    }
                }
            }

            Section("Фон") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ReaderThemePreset.allCases.filter { $0 != .customImage }) { preset in
                            Button {
                                settings.theme = preset
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(preset.defaultBackground)
                                        .frame(width: 56, height: 56)
                                        .overlay {
                                            Text("Аа")
                                                .font(.system(size: 16, design: .serif))
                                                .foregroundStyle(preset.defaultText)
                                        }
                                        .overlay {
                                            if settings.theme == preset {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(AppTheme.moss, lineWidth: 2)
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

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Загрузить свой фон", systemImage: "photo")
                }
                .onChange(of: photoItem) { _, item in
                    Task { await settings.setCustomBackground(from: item) }
                }

                if settings.customBackgroundImageData != nil {
                    VStack(alignment: .leading) {
                        Text("Прозрачность фона‑картинки")
                        Slider(value: $settings.backgroundImageOpacity, in: 0.1...0.9)
                    }
                    ColorPicker("Цвет подложки", selection: Binding(
                        get: { Color(hex: settings.customBackgroundHex) ?? .white },
                        set: { settings.customBackgroundHex = $0.toHex() }
                    ))
                    ColorPicker("Цвет текста", selection: Binding(
                        get: { Color(hex: settings.customTextHex) ?? .black },
                        set: { settings.customTextHex = $0.toHex() }
                    ))
                    Button("Убрать картинку", role: .destructive) {
                        settings.clearCustomBackground()
                    }
                }

                if settings.theme == .customColor {
                    ColorPicker("Цвет фона", selection: Binding(
                        get: { Color(hex: settings.customBackgroundHex) ?? .white },
                        set: { settings.customBackgroundHex = $0.toHex() }
                    ))
                    ColorPicker("Цвет текста", selection: Binding(
                        get: { Color(hex: settings.customTextHex) ?? .black },
                        set: { settings.customTextHex = $0.toHex() }
                    ))
                }
            }

            Section("Прочее") {
                Toggle("Не гасить экран", isOn: $settings.keepScreenOn)
            }

            Section("Превью") {
                ZStack {
                    settings.solidBackground
                    if let image = settings.backgroundImage {
                        image
                            .resizable()
                            .scaledToFill()
                            .opacity(settings.backgroundImageOpacity)
                    }
                    Text("В ту ночь дождь шёл не переставая, а фонарь у калитки качал жёлтый круг по мокрой брусчатке.")
                        .font(settings.fontFamily.font(size: settings.fontSize))
                        .foregroundStyle(settings.textColor)
                        .lineSpacing(settings.lineSpacing)
                        .padding(settings.marginHorizontal)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("Читалка")
        .navigationBarTitleDisplayMode(.inline)
    }
}
