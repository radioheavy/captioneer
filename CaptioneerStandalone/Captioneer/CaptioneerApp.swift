import SwiftUI
import AppKit
import Observation
#if canImport(Translation)
import Translation
#endif

@MainActor
@Observable
final class CaptioneerRuntime {
    let settings: CaptioneerSettings
    let obsIntegration: OBSIntegration
    let engine: CaptionEngine
    let overlayController: CaptionOverlayController

    init() {
        let settings = CaptioneerSettings()
        let obsIntegration = OBSIntegration(settings: settings)
        let engine = CaptionEngine(settings: settings, obsIntegration: obsIntegration)
        let overlayController = CaptionOverlayController(settings: settings, engine: engine)

        self.settings = settings
        self.obsIntegration = obsIntegration
        self.engine = engine
        self.overlayController = overlayController
    }

    func start() {
        overlayController.show()
        engine.startListening()
    }

    func stop() {
        engine.stopListening()
        overlayController.hide()
    }

    func toggle() {
        engine.isListening ? stop() : start()
    }

    func refreshOverlayLayout() {
        overlayController.refreshPositionIfVisible()
    }
}

@main
struct CaptioneerApp: App {
    @State private var runtime = CaptioneerRuntime()

    var body: some Scene {
        WindowGroup("Captioneer") {
            CaptioneerHomeView(runtime: runtime)
                .frame(minWidth: 760, minHeight: 560)
                .modifier(CaptionTranslationBridge(runtime: runtime))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)

        MenuBarExtra(
            "Captioneer",
            systemImage: runtime.engine.isListening ? "captions.bubble.fill" : "captions.bubble"
        ) {
            CaptioneerMenuBarView(runtime: runtime)
                .modifier(CaptionTranslationBridge(runtime: runtime))
        }
        .menuBarExtraStyle(.window)

        Settings {
            CaptioneerSettingsWindowView(runtime: runtime)
                .frame(minWidth: 760, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}

private struct CaptioneerHomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var runtime: CaptioneerRuntime

    var body: some View {
        ZStack {
            LinearGradient(colors: [baseBackgroundTop, baseBackgroundBottom],
                           startPoint: .top,
                           endPoint: .bottom)
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header
                controlBar
                liveCard
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.cyan.opacity(0.10))
                    .frame(width: 46, height: 46)

                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.teal)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Captioneer")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("On-device live transcription + translation for overlays and OBS")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusPill(
                title: runtime.engine.isListening ? "Listening" : "Idle",
                color: runtime.engine.isListening ? .green : .gray,
                systemImage: runtime.engine.isListening ? "waveform" : "pause.circle"
            )
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button {
                runtime.toggle()
            } label: {
                Label(runtime.engine.isListening ? "Stop Capture" : "Start Capture", systemImage: runtime.engine.isListening ? "stop.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(minWidth: 160, minHeight: 42)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(runtime.engine.isListening ? Color.red.opacity(0.88) : Color.teal.opacity(0.88))
            )
            .foregroundStyle(.white)

            Button("Clear") {
                runtime.engine.clearOutput()
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .frame(minWidth: 96, minHeight: 42)
            .background(secondaryButtonBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(secondaryButtonForeground)

            SettingsLink {
                Label("Settings", systemImage: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(minWidth: 120, minHeight: 42)
            }
            .buttonStyle(.plain)
            .background(secondaryButtonBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(secondaryButtonForeground)

            Spacer()

            statusPill(title: runtime.settings.sourceLanguageLabel, color: .blue, systemImage: "mic.fill")
            statusPill(title: runtime.settings.targetLanguageLabel, color: .teal, systemImage: "globe")
        }
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live Translation")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))

            if let error = runtime.engine.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.red.opacity(0.95))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if runtime.engine.lines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No translated caption yet.")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary.opacity(0.82))

                            Text("Press Start Capture and speak one sentence.")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                    } else {
                        ForEach(runtime.engine.lines) { line in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(line.translatedText)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text(line.sourceText)
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(innerCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .padding(6)
            }
            .frame(minHeight: 220, maxHeight: .infinity, alignment: .top)
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 14, y: 8)
    }

    private func statusPill(title: String, color: Color, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.primary.opacity(0.78))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(color.opacity(0.14), in: Capsule())
    }

    private var baseBackgroundTop: Color {
        colorScheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.15) : Color(nsColor: .windowBackgroundColor)
    }

    private var baseBackgroundBottom: Color {
        colorScheme == .dark ? Color(red: 0.07, green: 0.09, blue: 0.12) : Color.white
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : .white
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    private var innerCardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
    }

    private var secondaryButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    private var secondaryButtonForeground: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.primary.opacity(0.8)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.18) : .black.opacity(0.04)
    }

}

private struct CaptioneerSettingsWindowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var runtime: CaptioneerRuntime

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    colorScheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.15) : Color(nsColor: .windowBackgroundColor),
                    colorScheme == .dark ? Color(red: 0.07, green: 0.09, blue: 0.12) : Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text("Settings")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                ScrollView {
                    CaptioneerSettingsView(settings: runtime.settings) {
                        runtime.refreshOverlayLayout()
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(20)
        }
    }
}

private struct CaptioneerMenuBarView: View {
    @Bindable var runtime: CaptioneerRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(runtime.engine.isListening ? "Stop Listening" : "Start Listening") {
                runtime.toggle()
            }

            Button("Clear Captions") {
                runtime.engine.clearOutput()
            }

            Divider()

            Text("Latest")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(runtime.engine.translatedPreview.isEmpty ? "No output yet" : runtime.engine.translatedPreview)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(3)

            Divider()

            Button("Open Captioneer Window") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { !($0 is NSPanel) })?.makeKeyAndOrderFront(nil)
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 290)
    }
}

private struct CaptionTranslationBridge: ViewModifier {
    @Bindable var runtime: CaptioneerRuntime

    @ViewBuilder
    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(macOS 26.0, *) {
            content
                .task {
                    runtime.engine.bindTranslationSession(nil)
                }
        } else if #available(macOS 15.0, *), runtime.settings.shouldUseTranslationSession {
            content.translationTask(
                source: runtime.settings.translationSourceLanguage,
                target: runtime.settings.translationTargetLanguage
            ) { session in
                runtime.engine.bindTranslationSession(session)
            }
        } else {
            content
                .task {
                    if #available(macOS 15.0, *) {
                        runtime.engine.bindTranslationSession(nil)
                    }
                }
        }
        #else
        content
        #endif
    }
}
