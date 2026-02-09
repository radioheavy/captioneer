import SwiftUI
import AppKit
import Observation
import UniformTypeIdentifiers
#if canImport(Translation)
import Translation
#endif

enum CaptionOverlayPosition: String, CaseIterable, Identifiable {
    case top
    case bottom
    case floating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: return "Top (Dynamic Island)"
        case .bottom: return "Bottom (Subtitle)"
        case .floating: return "Floating"
        }
    }
}

struct CaptionLanguage: Identifiable, Hashable {
    let code: String
    let speechLocaleIdentifier: String
    let label: String

    var id: String { code }
}

@MainActor
@Observable
final class CaptioneerSettings {
    private enum Keys {
        static let sourceLanguageCode = "captioneer.sourceLanguageCode"
        static let targetLanguageCode = "captioneer.targetLanguageCode"
        static let overlayPosition = "captioneer.overlayPosition"
        static let overlayWidthRatio = "captioneer.overlayWidthRatio"
        static let overlayOffsetX = "captioneer.overlayOffsetX"
        static let overlayOffsetY = "captioneer.overlayOffsetY"
        static let floatingWidth = "captioneer.floatingWidth"
        static let floatingHeight = "captioneer.floatingHeight"
        static let obsOutputPath = "captioneer.obsOutputPath"
        static let streamingBufferWordCount = "captioneer.streamingBufferWordCount"
        static let maxVisibleLines = "captioneer.maxVisibleLines"
    }

    private let defaults = UserDefaults.standard

    var sourceLanguageCode: String {
        didSet { defaults.set(sourceLanguageCode, forKey: Keys.sourceLanguageCode) }
    }

    var targetLanguageCode: String {
        didSet { defaults.set(targetLanguageCode, forKey: Keys.targetLanguageCode) }
    }

    var overlayPosition: CaptionOverlayPosition {
        didSet { defaults.set(overlayPosition.rawValue, forKey: Keys.overlayPosition) }
    }

    var obsOutputPath: String {
        didSet { defaults.set(obsOutputPath, forKey: Keys.obsOutputPath) }
    }

    var overlayWidthRatio: Double {
        didSet { defaults.set(overlayWidthRatio, forKey: Keys.overlayWidthRatio) }
    }

    var overlayOffsetX: Double {
        didSet { defaults.set(overlayOffsetX, forKey: Keys.overlayOffsetX) }
    }

    var overlayOffsetY: Double {
        didSet { defaults.set(overlayOffsetY, forKey: Keys.overlayOffsetY) }
    }

    var floatingWidth: Double {
        didSet { defaults.set(floatingWidth, forKey: Keys.floatingWidth) }
    }

    var floatingHeight: Double {
        didSet { defaults.set(floatingHeight, forKey: Keys.floatingHeight) }
    }

    var streamingBufferWordCount: Int {
        didSet { defaults.set(streamingBufferWordCount, forKey: Keys.streamingBufferWordCount) }
    }

    var maxVisibleLines: Int {
        didSet { defaults.set(maxVisibleLines, forKey: Keys.maxVisibleLines) }
    }

    var sourceSpeechLocaleIdentifier: String {
        Self.sourceLanguages.first(where: { $0.code == sourceLanguageCode })?.speechLocaleIdentifier
            ?? Locale.current.identifier
    }

    var obsOutputURL: URL {
        URL(fileURLWithPath: (obsOutputPath as NSString).expandingTildeInPath)
    }

    var sourceLanguageLabel: String {
        Self.sourceLanguages.first(where: { $0.code == sourceLanguageCode })?.label
            ?? sourceLanguageCode
    }

    var targetLanguageLabel: String {
        Self.targetLanguages.first(where: { $0.code == targetLanguageCode })?.label
            ?? targetLanguageCode
    }

    #if canImport(Translation)
    @available(macOS 15.0, *)
    var translationSourceLanguage: Locale.Language? {
        guard sourceLanguageCode != "auto" else { return nil }
        return Locale.Language(identifier: sourceLanguageCode)
    }

    @available(macOS 15.0, *)
    var translationTargetLanguage: Locale.Language {
        Locale.Language(identifier: targetLanguageCode)
    }
    #endif

    var shouldUseTranslationSession: Bool {
        let sourceRoot = languageRoot(for: sourceLanguageCode)
        let targetRoot = languageRoot(for: targetLanguageCode)
        return sourceRoot != nil && targetRoot != nil && sourceRoot != targetRoot
    }

    init() {
        sourceLanguageCode = defaults.string(forKey: Keys.sourceLanguageCode) ?? "tr"
        targetLanguageCode = defaults.string(forKey: Keys.targetLanguageCode) ?? "en"

        if let rawOverlay = defaults.string(forKey: Keys.overlayPosition),
           let position = CaptionOverlayPosition(rawValue: rawOverlay) {
            overlayPosition = position
        } else {
            overlayPosition = .top
        }

        obsOutputPath = defaults.string(forKey: Keys.obsOutputPath) ?? Self.defaultOBSPath

        let storedOverlayWidth = defaults.double(forKey: Keys.overlayWidthRatio)
        overlayWidthRatio = min(0.95, max(0.40, storedOverlayWidth == 0 ? 0.82 : storedOverlayWidth))

        overlayOffsetX = min(420, max(-420, defaults.double(forKey: Keys.overlayOffsetX)))
        overlayOffsetY = min(320, max(-320, defaults.double(forKey: Keys.overlayOffsetY)))
        floatingWidth = min(1400, max(420, defaults.double(forKey: Keys.floatingWidth) == 0 ? 820 : defaults.double(forKey: Keys.floatingWidth)))
        floatingHeight = min(520, max(120, defaults.double(forKey: Keys.floatingHeight) == 0 ? 220 : defaults.double(forKey: Keys.floatingHeight)))

        let storedBufferCount = defaults.integer(forKey: Keys.streamingBufferWordCount)
        streamingBufferWordCount = max(3, storedBufferCount == 0 ? 6 : storedBufferCount)

        let storedLineCount = defaults.integer(forKey: Keys.maxVisibleLines)
        maxVisibleLines = min(8, max(2, storedLineCount == 0 ? 4 : storedLineCount))
    }

    static let sourceLanguages: [CaptionLanguage] = [
        CaptionLanguage(code: "auto", speechLocaleIdentifier: Locale.current.identifier, label: "Auto Detect"),
        CaptionLanguage(code: "tr", speechLocaleIdentifier: "tr-TR", label: "Turkish"),
        CaptionLanguage(code: "en", speechLocaleIdentifier: "en-US", label: "English"),
        CaptionLanguage(code: "de", speechLocaleIdentifier: "de-DE", label: "German"),
        CaptionLanguage(code: "fr", speechLocaleIdentifier: "fr-FR", label: "French"),
        CaptionLanguage(code: "es", speechLocaleIdentifier: "es-ES", label: "Spanish"),
        CaptionLanguage(code: "it", speechLocaleIdentifier: "it-IT", label: "Italian"),
        CaptionLanguage(code: "pt", speechLocaleIdentifier: "pt-PT", label: "Portuguese"),
        CaptionLanguage(code: "ru", speechLocaleIdentifier: "ru-RU", label: "Russian"),
        CaptionLanguage(code: "ar", speechLocaleIdentifier: "ar-SA", label: "Arabic")
    ]

    static let targetLanguages: [CaptionLanguage] = sourceLanguages.filter { $0.code != "auto" }

    static var defaultOBSPath: String {
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        return desktop.appendingPathComponent("captioneer-live.txt").path
    }

    private func languageRoot(for code: String?) -> String? {
        guard let code else { return nil }
        return code.split(separator: "-").first.map { String($0).lowercased() }
    }
}

struct CaptioneerSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var settings: CaptioneerSettings
    var onOverlayLayoutChange: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionCard("Languages") {
                row("Source") {
                    Picker("Source Language", selection: $settings.sourceLanguageCode) {
                        ForEach(CaptioneerSettings.sourceLanguages) { language in
                            Text(language.label).tag(language.code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                row("Target") {
                    Picker("Target Language", selection: $settings.targetLanguageCode) {
                        ForEach(CaptioneerSettings.targetLanguages) { language in
                            Text(language.label).tag(language.code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }

            sectionCard("Overlay") {
                row("Position") {
                    Picker("Position", selection: $settings.overlayPosition) {
                        ForEach(CaptionOverlayPosition.allCases) { position in
                            Text(position.label).tag(position)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 430)
                }

                sliderRow("Width", value: "\(Int(settings.overlayWidthRatio * 100))%") {
                    Slider(value: $settings.overlayWidthRatio, in: 0.40...0.95, step: 0.01)
                }

                sliderRow("Horizontal", value: "\(Int(settings.overlayOffsetX)) px") {
                    Slider(value: $settings.overlayOffsetX, in: -420...420, step: 1)
                }

                sliderRow("Vertical", value: "\(Int(settings.overlayOffsetY)) px") {
                    Slider(value: $settings.overlayOffsetY, in: -320...320, step: 1)
                }

                row("Visible lines") {
                    Stepper(value: $settings.maxVisibleLines, in: 2...8) {
                        Text("\(settings.maxVisibleLines)")
                            .frame(width: 36, alignment: .trailing)
                    }
                    .frame(width: 220, alignment: .trailing)
                }

                if settings.overlayPosition == .floating {
                    sliderRow("Floating Width", value: "\(Int(settings.floatingWidth)) px") {
                        Slider(value: $settings.floatingWidth, in: 420...1400, step: 1)
                    }

                    sliderRow("Floating Height", value: "\(Int(settings.floatingHeight)) px") {
                        Slider(value: $settings.floatingHeight, in: 120...520, step: 1)
                    }
                }

                HStack {
                    Spacer()
                    Button("Reset Position") {
                        settings.overlayOffsetX = 0
                        settings.overlayOffsetY = 0
                    }
                    .buttonStyle(.borderless)
                }
            }

            sectionCard("Output") {
                sliderRow("Context buffer", value: "\(settings.streamingBufferWordCount) words") {
                    Slider(value: Binding(
                        get: { Double(settings.streamingBufferWordCount) },
                        set: { settings.streamingBufferWordCount = Int($0) }
                    ), in: 3...14, step: 1)
                }

                row("OBS file") {
                    HStack(spacing: 8) {
                        TextField("/path/to/captioneer-live.txt", text: $settings.obsOutputPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse") {
                            chooseOBSPath()
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(width: 430)
                }
            }

            Text("Privacy-first: Speech recognition and captions are processed locally on your Mac.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .onChange(of: settings.overlayPosition) { _, _ in
            onOverlayLayoutChange?()
        }
        .onChange(of: settings.overlayWidthRatio) { _, _ in
            onOverlayLayoutChange?()
        }
        .onChange(of: settings.overlayOffsetX) { _, _ in
            onOverlayLayoutChange?()
        }
        .onChange(of: settings.overlayOffsetY) { _, _ in
            onOverlayLayoutChange?()
        }
        .onChange(of: settings.maxVisibleLines) { _, _ in
            onOverlayLayoutChange?()
        }
        .onChange(of: settings.floatingWidth) { _, _ in
            onOverlayLayoutChange?()
        }
        .onChange(of: settings.floatingHeight) { _, _ in
            onOverlayLayoutChange?()
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.82))
            content()
        }
        .padding(12)
        .background(sectionBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(sectionBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.75))
                .frame(width: 120, alignment: .leading)
            Spacer(minLength: 0)
            content()
        }
    }

    @ViewBuilder
    private func sliderRow<Content: View>(_ label: String, value: String, @ViewBuilder slider: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.75))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            slider()
        }
    }

    private var sectionBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : .white
    }

    private var sectionBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    private func chooseOBSPath() {
        let panel = NSSavePanel()
        panel.title = "OBS Caption Output"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "captioneer-live.txt"
        panel.canCreateDirectories = true
        panel.directoryURL = settings.obsOutputURL.deletingLastPathComponent()

        if panel.runModal() == .OK, let selectedURL = panel.url {
            settings.obsOutputPath = selectedURL.path
        }
    }
}
