import SwiftUI
import AppKit
import Observation

@MainActor
final class CaptionOverlayController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let settings: CaptioneerSettings
    private let engine: CaptionEngine

    init(settings: CaptioneerSettings, engine: CaptionEngine) {
        self.settings = settings
        self.engine = engine
        super.init()
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

        configurePanelStyle(panel)

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
        panel.delegate = self
        configurePanelStyle(panel)

        self.panel = panel
    }

    private func configurePanelStyle(_ panel: NSPanel) {
        if settings.overlayPosition == .floating {
            panel.styleMask = [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel]
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.minSize = NSSize(width: 420, height: 120)
            panel.maxSize = NSSize(width: 1400, height: 520)
        } else {
            panel.styleMask = [.borderless, .nonactivatingPanel]
            panel.isMovableByWindowBackground = false
            panel.hasShadow = false
        }
    }

    private func targetFrame() -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: 200, y: 200, width: 720, height: 190)
        }

        let visible = screen.visibleFrame
        let width = settings.overlayPosition == .floating
            ? min(max(420, CGFloat(settings.floatingWidth)), 1400)
            : min(max(420, visible.width * settings.overlayWidthRatio), 1400)
        let baseHeight = max(110, min(220, CGFloat(settings.maxVisibleLines) * 27 + 44))
        let height: CGFloat = settings.overlayPosition == .floating
            ? min(max(120, CGFloat(settings.floatingHeight)), 520)
            : baseHeight
        let defaultX = visible.midX - (width / 2)

        let defaultY: CGFloat
        switch settings.overlayPosition {
        case .top:
            defaultY = visible.maxY - height - 12
        case .bottom:
            defaultY = visible.minY + 24
        case .floating:
            defaultY = visible.midY - (height / 2)
        }

        let offsetX = CGFloat(settings.overlayOffsetX)
        let offsetY = CGFloat(settings.overlayOffsetY)
        let proposedX = defaultX + offsetX
        let proposedY = defaultY + offsetY

        let minX = visible.minX
        let maxX = visible.maxX - width
        let minY = visible.minY
        let maxY = visible.maxY - height

        let x = min(max(proposedX, minX), maxX)
        let y = min(max(proposedY, minY), maxY)

        return NSRect(x: x, y: y, width: width, height: height)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard settings.overlayPosition == .floating else { return }
        guard let panel else { return }
        settings.floatingWidth = panel.frame.width
        settings.floatingHeight = panel.frame.height
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
