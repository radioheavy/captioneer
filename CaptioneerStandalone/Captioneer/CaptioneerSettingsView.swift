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
    @Bindable var settings: CaptioneerSettings
    var onOverlayLayoutChange: (() -> Void)?

    var body: some View {
        Form {
            Section("Languages") {
                Picker("Source Language", selection: $settings.sourceLanguageCode) {
                    ForEach(CaptioneerSettings.sourceLanguages) { language in
                        Text(language.label).tag(language.code)
                    }
                }

                Picker("Target Language", selection: $settings.targetLanguageCode) {
                    ForEach(CaptioneerSettings.targetLanguages) { language in
                        Text(language.label).tag(language.code)
                    }
                }
            }

            Section("Overlay") {
                Picker("Position", selection: $settings.overlayPosition) {
                    ForEach(CaptionOverlayPosition.allCases) { position in
                        Text(position.label).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Width")
                        Spacer()
                        Text("\(Int(settings.overlayWidthRatio * 100))%")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $settings.overlayWidthRatio, in: 0.40...0.95, step: 0.01)
                }

                Stepper(value: $settings.maxVisibleLines, in: 2...8) {
                    Text("Visible lines: \(settings.maxVisibleLines)")
                }
            }

            Section("Context Buffer") {
                Stepper(value: $settings.streamingBufferWordCount, in: 3...14) {
                    Text("Translate after ~\(settings.streamingBufferWordCount) words")
                }

                Text("Longer buffer = daha doğru cümle çevirisi, daha az kelime-kelime hata.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("OBS Output") {
                TextField("/path/to/captioneer-live.txt", text: $settings.obsOutputPath)
                    .textFieldStyle(.roundedBorder)

                Button("Choose File") {
                    chooseOBSPath()
                }
            }

            Section {
                Text("Privacy-first: Mikrofon tanıma on-device çalışır; OBS çıktısı sadece local .txt dosyasına yazılır.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.overlayPosition) { _, _ in
            onOverlayLayoutChange?()
        }
        .onChange(of: settings.overlayWidthRatio) { _, _ in
            onOverlayLayoutChange?()
        }
        .onChange(of: settings.maxVisibleLines) { _, _ in
            onOverlayLayoutChange?()
        }
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
