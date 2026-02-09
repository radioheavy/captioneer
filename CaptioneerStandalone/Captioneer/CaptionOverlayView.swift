import SwiftUI
import AppKit
import Observation

@MainActor
final class CaptionOverlayController {
    private var panel: NSPanel?
    private let settings: CaptioneerSettings
    private let engine: CaptionEngine

    init(settings: CaptioneerSettings, engine: CaptionEngine) {
        self.settings = settings
        self.engine = engine
    }

    var isVisible: Bool {
        panel != nil
    }

    func show() {
        if panel == nil {
            createPanel()
        }

        refreshPositionIfVisible(animated: false)
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    func refreshPositionIfVisible(animated: Bool = true) {
        guard let panel else { return }

        panel.isMovableByWindowBackground = settings.overlayPosition == .floating
        panel.hasShadow = settings.overlayPosition == .floating

        let frame = targetFrame()
        panel.setFrame(frame, display: true, animate: animated)
    }

    private func createPanel() {
        let frame = targetFrame()
        let view = CaptionOverlayView(engine: engine, settings: settings)
        let contentView = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = settings.overlayPosition == .floating
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = settings.overlayPosition == .floating
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.contentView = contentView

        self.panel = panel
    }

    private func targetFrame() -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: 200, y: 200, width: 720, height: 190)
        }

        let visible = screen.visibleFrame
        let width = min(max(420, visible.width * settings.overlayWidthRatio), 1400)
        let baseHeight = max(110, min(220, CGFloat(settings.maxVisibleLines) * 27 + 44))
        let height: CGFloat = settings.overlayPosition == .floating ? baseHeight + 8 : baseHeight
        let x = visible.midX - (width / 2)

        let y: CGFloat
        switch settings.overlayPosition {
        case .top:
            y = visible.maxY - height - 12
        case .bottom:
            y = visible.minY + 24
        case .floating:
            y = visible.midY - (height / 2)
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }
}

struct CaptionOverlayView: View {
    @Bindable var engine: CaptionEngine
    @Bindable var settings: CaptioneerSettings

    private var visibleLines: [CaptionLine] {
        Array(engine.lines.suffix(settings.maxVisibleLines))
    }

    var body: some View {
        ZStack {
            backgroundContainer

            VStack(alignment: .leading, spacing: 10) {
                if visibleLines.isEmpty {
                    Text(engine.isListening ? "Listening..." : "Captioneer is idle")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)

                    if !engine.recognizedText.isEmpty {
                        Text(engine.recognizedText)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    ForEach(Array(visibleLines.enumerated()), id: \.element.id) { index, line in
                        let age = visibleLines.count - index - 1
                        CaptionOverlayLineView(line: line, age: age)
                    }
                }

                if settings.sourceLanguageCode == "auto",
                   let detected = engine.detectedSourceLanguageCode {
                    Text("Detected source: \(Locale.current.localizedString(forLanguageCode: detected) ?? detected)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(16)
        }
        .animation(.easeInOut(duration: 0.25), value: visibleLines.map(\.id))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var backgroundContainer: some View {
        switch settings.overlayPosition {
        case .top:
            Capsule(style: .continuous)
                .fill(.black.opacity(0.86))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        case .bottom, .floating:
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

private struct CaptionOverlayLineView: View {
    let line: CaptionLine
    let age: Int

    private var textOpacity: Double {
        max(0.22, 1 - (Double(age) * 0.24))
    }

    private var fontSize: CGFloat {
        let reduced = CGFloat(min(age, 3)) * 2
        return max(18, 26 - reduced)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.translatedText)
                .font(.system(size: fontSize, weight: age == 0 ? .semibold : .medium, design: .rounded))
                .foregroundStyle(.white.opacity(textOpacity))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .blur(radius: age == 0 ? 0 : CGFloat(age) * 0.35)

            if age == 0 {
                Text(line.sourceText)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
