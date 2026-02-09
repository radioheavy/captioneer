import Foundation
import Observation
import Speech
import AVFoundation
import NaturalLanguage
#if canImport(Translation)
import Translation
#endif

struct CaptionLine: Identifiable, Equatable {
    let id = UUID()
    let sequence: Int
    let sourceText: String
    let translatedText: String
    let createdAt: Date
}

@MainActor
@Observable
final class CaptionEngine {
    var isListening = false
    var isSpeaking = false
    var errorMessage: String?

    var recognizedText: String = ""
    var translatedPreview: String = ""
    var lines: [CaptionLine] = []
    var detectedSourceLanguageCode: String?
    var audioLevels: [Double] = Array(repeating: 0, count: 24)

    private let settings: CaptioneerSettings
    private let obsIntegration: OBSIntegration
    private let translator = OnDeviceCaptionTranslator()

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()

    private var pendingWords: [String] = []
    private var lastSnapshotWords: [String] = []
    private var translatedStableWordCount = 0

    private var stagedLines: [Int: CaptionLine] = [:]
    private var nextSequence = 0
    private var lastFlushAt = Date.distantPast
    private var isStopping = false
    private var silenceFinalizeTask: Task<Void, Never>?
    private var lastCommittedTranscript: String = ""

    init(settings: CaptioneerSettings, obsIntegration: OBSIntegration) {
        self.settings = settings
        self.obsIntegration = obsIntegration
    }

    func startListening() {
        guard !isListening else { return }

        errorMessage = nil
        recognizedText = ""
        translatedPreview = ""
        pendingWords.removeAll()
        lastSnapshotWords.removeAll()
        translatedStableWordCount = 0
        lastCommittedTranscript = ""
        silenceFinalizeTask?.cancel()
        silenceFinalizeTask = nil
        isStopping = false

        Task {
            let speechAuthorized = await requestSpeechAuthorization()
            let micAuthorized = await requestMicrophoneAccess()

            guard speechAuthorized, micAuthorized else {
                await MainActor.run {
                    self.errorMessage = "Speech or microphone permission denied."
                }
                return
            }

            await MainActor.run {
                self.beginRecognition()
            }
        }
    }

    func stopListening() {
        isStopping = true
        silenceFinalizeTask?.cancel()
        silenceFinalizeTask = nil
        if !recognizedText.isEmpty {
            commitFinalSentence(recognizedText)
        }
        cleanupRecognition()
        isListening = false
        isSpeaking = false
    }

    func clearOutput() {
        recognizedText = ""
        translatedPreview = ""
        lines.removeAll()
        stagedLines.removeAll()
        nextSequence = 0
        obsIntegration.clear()
    }

    #if canImport(Translation)
    @available(macOS 15.0, *)
    func bindTranslationSession(_ session: TranslationSession?) {
        Task {
            await translator.updateSession(session)
        }
    }
    #endif

    private func beginRecognition() {
        cleanupRecognition()

        let sourceLocale = Locale(identifier: settings.sourceSpeechLocaleIdentifier)
        speechRecognizer = SFSpeechRecognizer(locale: sourceLocale)

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer is unavailable for \(settings.sourceLanguageLabel)."
            return
        }

        guard speechRecognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device speech recognition is not available for \(settings.sourceLanguageLabel). Choose another source language."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            request.append(buffer)

            let level = Self.audioLevel(from: buffer)
            Task { @MainActor [weak self] in
                self?.appendAudioLevel(level)
            }
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                Task { @MainActor [weak self] in
                    self?.consume(result: result)
                }
            }

            if let error {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.isStopping { return }
                    self.errorMessage = error.localizedDescription
                    self.stopListening()
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            errorMessage = "Audio engine failed: \(error.localizedDescription)"
            stopListening()
        }
    }

    private func consume(result: SFSpeechRecognitionResult) {
        let transcript = Self.normalizeWhitespace(result.bestTranscription.formattedString)
        guard !transcript.isEmpty else { return }

        recognizedText = transcript

        let words = Self.tokenize(transcript)
        guard !words.isEmpty else { return }

        if hasBacktrackingRewrite(newWords: words) {
            pendingWords.removeAll()
            translatedStableWordCount = 0
        }

        let unstableTailCount: Int
        if result.isFinal {
            unstableTailCount = 0
        } else if words.count >= 6 {
            unstableTailCount = 2
        } else if words.count >= 3 {
            unstableTailCount = 1
        } else {
            unstableTailCount = 0
        }
        let stableCount = max(words.count - unstableTailCount, 0)

        if stableCount > translatedStableWordCount {
            let stableSlice = words[translatedStableWordCount..<stableCount]
            pendingWords.append(contentsOf: stableSlice)
            translatedStableWordCount = stableCount
        }

        lastSnapshotWords = words

        if result.isFinal {
            silenceFinalizeTask?.cancel()
            silenceFinalizeTask = nil
            pendingWords.removeAll()
            commitFinalSentence(transcript)
            translatedStableWordCount = 0
            lastSnapshotWords.removeAll()
            return
        }

        scheduleSilenceBasedFinalize(for: transcript)
    }

    private func scheduleSilenceBasedFinalize(for transcript: String) {
        silenceFinalizeTask?.cancel()

        silenceFinalizeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                guard self.isListening else { return }
                let current = Self.normalizeWhitespace(self.recognizedText)
                guard !current.isEmpty else { return }
                guard current == Self.normalizeWhitespace(transcript) else { return }
                self.commitFinalSentence(current)
            }
        }
    }

    private func shouldCommitPendingContext() -> Bool {
        guard !pendingWords.isEmpty else { return false }
        let elapsed = Date().timeIntervalSince(lastFlushAt)
        let targetWords = max(2, settings.streamingBufferWordCount)

        if pendingWords.count >= targetWords {
            return true
        }

        if let lastWord = pendingWords.last,
           let lastChar = lastWord.last,
           ".!?;:".contains(lastChar) {
            return true
        }

        if pendingWords.count >= 2 && elapsed >= 1.5 {
            return true
        }

        if pendingWords.count >= 1 && elapsed >= 3.0 {
            return true
        }

        return false
    }

    private func commitPendingContext(force: Bool) {
        guard !pendingWords.isEmpty else { return }

        if !force {
            let elapsed = Date().timeIntervalSince(lastFlushAt)
            let targetWords = max(2, settings.streamingBufferWordCount)
            let hasEndingPunctuation = pendingWords.last?.last.map { ".!?;:".contains($0) } ?? false

            let canFlush = pendingWords.count >= targetWords
                || hasEndingPunctuation
                || (pendingWords.count >= 2 && elapsed >= 1.5)
                || (pendingWords.count >= 1 && elapsed >= 3.0)

            guard canFlush else { return }
        }

        let sourceChunk = Self.normalizeWhitespace(pendingWords.joined(separator: " "))
        guard !sourceChunk.isEmpty else {
            pendingWords.removeAll()
            return
        }

        pendingWords.removeAll()
        lastFlushAt = Date()

        let sequence = nextSequence
        nextSequence += 1

        let targetLanguageCode = settings.targetLanguageCode
        let sourceLanguageCode = resolveSourceLanguage(for: sourceChunk)

        Task { [weak self] in
            guard let self else { return }
            let translated = await self.translator.translate(
                sourceChunk,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode
            )

            await MainActor.run {
                let line = CaptionLine(
                    sequence: sequence,
                    sourceText: sourceChunk,
                    translatedText: translated,
                    createdAt: Date()
                )
                self.stage(line)
            }
        }
    }

    private func commitFinalSentence(_ transcript: String) {
        let sourceChunk = Self.normalizeWhitespace(transcript)
        guard !sourceChunk.isEmpty else { return }
        guard sourceChunk != lastCommittedTranscript else { return }
        lastCommittedTranscript = sourceChunk

        lastFlushAt = Date()

        let sequence = nextSequence
        nextSequence += 1

        let targetLanguageCode = settings.targetLanguageCode
        let sourceLanguageCode = resolveSourceLanguage(for: sourceChunk)

        Task { [weak self] in
            guard let self else { return }
            let translated = await self.translator.translate(
                sourceChunk,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode
            )

            await MainActor.run {
                let line = CaptionLine(
                    sequence: sequence,
                    sourceText: sourceChunk,
                    translatedText: translated,
                    createdAt: Date()
                )
                self.stage(line)
            }
        }
    }

    private func stage(_ line: CaptionLine) {
        stagedLines[line.sequence] = line

        let ordered = stagedLines.values.sorted { $0.sequence < $1.sequence }
        let latest = Array(ordered.suffix(settings.maxVisibleLines))
        lines = latest
        translatedPreview = latest.last?.translatedText ?? translatedPreview

        if stagedLines.count > 120 {
            let keep = ordered.suffix(60)
            stagedLines = Dictionary(uniqueKeysWithValues: keep.map { ($0.sequence, $0) })
        }

        obsIntegration.publish(lines: latest)
    }

    private func resolveSourceLanguage(for text: String) -> String? {
        if settings.sourceLanguageCode != "auto" {
            detectedSourceLanguageCode = settings.sourceLanguageCode
            return settings.sourceLanguageCode
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let detected = recognizer.dominantLanguage?.rawValue {
            detectedSourceLanguageCode = detected
            return detected
        }

        if let heuristic = heuristicSourceLanguage(for: text) {
            detectedSourceLanguageCode = heuristic
            return heuristic
        }

        if let localeRoot = languageRoot(from: settings.sourceSpeechLocaleIdentifier) {
            detectedSourceLanguageCode = localeRoot
            return localeRoot
        }

        detectedSourceLanguageCode = nil
        return nil
    }

    private func appendAudioLevel(_ level: Double) {
        audioLevels.append(level)
        if audioLevels.count > 24 {
            audioLevels.removeFirst()
        }

        let recent = audioLevels.suffix(6)
        let average = recent.reduce(0, +) / Double(max(1, recent.count))
        isSpeaking = average > 0.04
    }

    private func hasBacktrackingRewrite(newWords: [String]) -> Bool {
        guard !lastSnapshotWords.isEmpty else { return false }
        guard translatedStableWordCount > 0 else { return false }

        let compareCount = min(translatedStableWordCount, min(newWords.count, lastSnapshotWords.count))
        guard compareCount > 0 else { return false }

        return Array(newWords.prefix(compareCount)) != Array(lastSnapshotWords.prefix(compareCount))
    }

    private func languageRoot(from localeIdentifier: String) -> String? {
        localeIdentifier
            .split(separator: "-")
            .first
            .map { String($0).lowercased() }
    }

    private func heuristicSourceLanguage(for text: String) -> String? {
        let lowercased = text.lowercased()

        if lowercased.contains(where: { "ğüşöçıİı".contains($0) }) {
            return "tr"
        }

        let turkishHints = ["bir", "ve", "için", "de", "bu", "şu", "çok", "ama", "çünkü", "ile"]
        let words = lowercased.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let hintCount = words.filter { turkishHints.contains($0) }.count
        if hintCount >= 2 {
            return "tr"
        }

        return nil
    }

    private func cleanupRecognition() {
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func audioLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = channelData[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        return min(Double(rms * 5), 1.0)
    }
}

private actor OnDeviceCaptionTranslator {
    #if canImport(Translation)
    private var translationSession: TranslationSession?

    private var directSessions: [String: TranslationSession] = [:]

    @available(macOS 15.0, *)
    func updateSession(_ session: TranslationSession?) {
        translationSession = session
    }
    #endif

    func translate(_ text: String, sourceLanguageCode: String?, targetLanguageCode: String) async -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        if languageRoot(sourceLanguageCode) == languageRoot(targetLanguageCode) {
            return normalized
        }

        #if canImport(Translation)
        if #available(macOS 15.0, *), let translationSession {
            if let translated = await translateWithTimeout(
                session: translationSession,
                text: normalized,
                timeoutSeconds: 1.4
            ) {
                return translated
            }
        }

        if #available(macOS 26.0, *) {
            if let directSession = await directSession(
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode
            ) {
                if let translated = await translateWithTimeout(
                    session: directSession,
                    text: normalized,
                    timeoutSeconds: 1.4
                ) {
                    return translated
                }
            }
        }
        #endif

        return await MainActor.run {
            RuleBasedFallbackTranslator.translate(
                normalized,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode
            )
        }
    }

    private func languageRoot(_ code: String?) -> String? {
        guard let code else { return nil }
        return code.split(separator: "-").first.map { String($0).lowercased() }
    }

    #if canImport(Translation)
    @available(macOS 26.0, *)
    private func directSession(sourceLanguageCode: String?, targetLanguageCode: String) async -> TranslationSession? {
        guard let sourceLanguageCode else { return nil }
        let source = Locale.Language(identifier: sourceLanguageCode)
        let target = Locale.Language(identifier: targetLanguageCode)
        let key = "\(sourceLanguageCode.lowercased())->\(targetLanguageCode.lowercased())"

        if let cached = directSessions[key] {
            if await cached.isReady {
                return cached
            }

            do {
                try await cached.prepareTranslation()
                return cached
            } catch {
                return nil
            }
        }

        let session = TranslationSession(installedSource: source, target: target)
        do {
            if !(await session.isReady) {
                try await session.prepareTranslation()
            }
            directSessions[key] = session
            return session
        } catch {
            return nil
        }
    }

    @available(macOS 15.0, *)
    private func translateWithTimeout(
        session: TranslationSession,
        text: String,
        timeoutSeconds: Double
    ) async -> String? {
        await withTaskGroup(of: TranslationRaceResult.self) { group in
            group.addTask {
                if let response = try? await session.translate(text),
                   !response.targetText.isEmpty {
                    return .translated(response.targetText)
                }
                return .noTranslation
            }

            group.addTask {
                let nanos = UInt64(max(0.1, timeoutSeconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return .timedOut
            }

            guard let first = await group.next() else {
                group.cancelAll()
                return nil
            }

            group.cancelAll()
            switch first {
            case .translated(let text):
                return text
            case .noTranslation, .timedOut:
                return nil
            }
        }
    }
    #endif
}

private enum TranslationRaceResult {
    case translated(String)
    case noTranslation
    case timedOut
}

private enum RuleBasedFallbackTranslator {
    private static let trToEn: [String: String] = [
        "merhaba": "hello",
        "selam": "hi",
        "evet": "yes",
        "hayır": "no",
        "teşekkürler": "thanks",
        "teşekkür": "thanks",
        "günaydın": "good morning",
        "iyi": "good",
        "akşamlar": "evening",
        "nasılsın": "how are you",
        "bugün": "today",
        "yarın": "tomorrow",
        "dün": "yesterday",
        "toplantı": "meeting",
        "başlıyoruz": "we are starting",
        "başladı": "started",
        "tamam": "okay",
        "oldu": "done",
        "tekrar": "again",
        "lütfen": "please",
        "bekleyin": "wait",
        "harika": "great",
        "mükemmel": "excellent",
        "çalışıyor": "it works",
        "çalışmıyor": "it does not work",
        "mikrofon": "microphone",
        "çeviri": "translation",
        "altyazı": "caption",
        "başarı": "success"
    ]

    static func translate(_ text: String, sourceLanguageCode: String?, targetLanguageCode: String) -> String {
        let sourceRoot = languageRoot(sourceLanguageCode)
        let targetRoot = languageRoot(targetLanguageCode)

        guard sourceRoot == "tr", targetRoot == "en" else {
            return text
        }

        let transformed = text
            .split(whereSeparator: { $0.isWhitespace })
            .map { replaceToken(String($0)) }
            .joined(separator: " ")

        return transformed.isEmpty ? text : transformed
    }

    private static func replaceToken(_ token: String) -> String {
        let punctuation = CharacterSet.punctuationCharacters
        let characters = Array(token)
        guard !characters.isEmpty else { return token }

        var leadingCount = 0
        while leadingCount < characters.count,
              characters[leadingCount].unicodeScalars.allSatisfy({ punctuation.contains($0) }) {
            leadingCount += 1
        }

        var trailingCount = 0
        while trailingCount < (characters.count - leadingCount),
              characters[characters.count - 1 - trailingCount].unicodeScalars.allSatisfy({ punctuation.contains($0) }) {
            trailingCount += 1
        }

        let coreLength = characters.count - leadingCount - trailingCount
        guard coreLength > 0 else { return token }

        let leading = String(characters.prefix(leadingCount))
        let trailing = trailingCount > 0 ? String(characters.suffix(trailingCount)) : ""
        let core = String(characters[leadingCount..<(leadingCount + coreLength)])

        let lowerCore = core.lowercased()
        guard let translatedCore = trToEn[lowerCore] else { return token }

        let adjusted = preserveCapitalization(from: core, to: translatedCore)
        return leading + adjusted + trailing
    }

    private static func preserveCapitalization(from original: String, to translated: String) -> String {
        guard let first = original.first else { return translated }
        guard first.isUppercase else { return translated }
        return translated.prefix(1).uppercased() + translated.dropFirst()
    }

    private static func languageRoot(_ code: String?) -> String? {
        guard let code else { return nil }
        return code.split(separator: "-").first.map { String($0).lowercased() }
    }
}
