import Foundation

@MainActor
final class OBSIntegration {
    private let settings: CaptioneerSettings
    private let ioQueue = DispatchQueue(label: "captioneer.obs.integration", qos: .utility)

    init(settings: CaptioneerSettings) {
        self.settings = settings
    }

    func publish(lines: [CaptionLine]) {
        let payload = lines.map(\.translatedText).joined(separator: "\n")
        write(payload)
    }

    func clear() {
        write("")
    }

    private func write(_ text: String) {
        let destination = settings.obsOutputURL

        ioQueue.async {
            do {
                let parent = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
                try Data(text.utf8).write(to: destination, options: .atomic)
            } catch {
                // OBS yazımı best-effort; dosya hatası caption akışını durdurmamalı.
            }
        }
    }
}
