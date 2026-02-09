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
                .frame(minWidth: 560, minHeight: 650)
                .modifier(CaptionTranslationBridge(runtime: runtime))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra(
            "Captioneer",
            systemImage: runtime.engine.isListening ? "captions.bubble.fill" : "captions.bubble"
        ) {
            CaptioneerMenuBarView(runtime: runtime)
                .modifier(CaptionTranslationBridge(runtime: runtime))
        }
        .menuBarExtraStyle(.window)
    }
}

private struct CaptioneerHomeView: View {
    @Bindable var runtime: CaptioneerRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let error = runtime.engine.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
            }

            GroupBox("Live Translation") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if runtime.engine.lines.isEmpty {
                            Text("No translated caption yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(runtime.engine.lines) { line in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.translatedText)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    Text(line.sourceText)
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(minHeight: 140, maxHeight: 220)
            }

            GroupBox("Settings") {
                CaptioneerSettingsView(settings: runtime.settings) {
                    runtime.refreshOverlayLayout()
                }
                .frame(maxHeight: 420)
            }
        }
        .padding(18)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Captioneer")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text("On-device live transcription + translation for overlays and OBS")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                runtime.toggle()
            } label: {
                Label(runtime.engine.isListening ? "Stop" : "Start", systemImage: runtime.engine.isListening ? "stop.fill" : "play.fill")
                    .frame(minWidth: 92)
            }
            .buttonStyle(.borderedProminent)

            Button("Clear") {
                runtime.engine.clearOutput()
            }
            .buttonStyle(.bordered)
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
