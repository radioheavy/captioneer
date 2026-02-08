//
//  ContentView.swift
//  Textream
//
//  Created by Fatih Kadir Akın on 8.02.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var text: String = """
Welcome to Textream! This is your personal teleprompter that sits right below your MacBook's notch. [smile]

As you read aloud, the text will highlight in real-time, following your voice. The speech recognition matches your words and keeps track of your progress. [pause]

You can pause at any time, go back and re-read sections, and the highlighting will follow along. When you finish reading all the text, the overlay will automatically close with a smooth animation. [nod]

Try reading this passage out loud to see how the highlighting works. The waveform at the bottom shows your voice activity, and you'll see the last few words you spoke displayed next to it.

Happy presenting! [wave]
"""
    @State private var isRunning = false
    @State private var showSettings = false
    @FocusState private var isTextFocused: Bool
    private let service = TextreamService.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Text editor - full window
            TextEditor(text: $text)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(20)
                .padding(.top, 12) // Extra space for window drag area
                .focused($isTextFocused)

            // Floating action button
            Button {
                if isRunning {
                    stop()
                } else {
                    run()
                }
            } label: {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(isRunning ? Color.red : Color.accentColor)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .padding(20)
            .disabled(!isRunning && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunning ? 0.4 : 1)
        }
        .frame(minWidth: 360, minHeight: 240)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: NotchSettings.shared)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .onAppear {
            if TextreamService.shared.launchedExternally {
                DispatchQueue.main.async {
                    for window in NSApp.windows where !(window is NSPanel) {
                        window.orderOut(nil)
                    }
                }
            } else {
                isTextFocused = true
            }
        }
    }

    private func run() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        service.onOverlayDismissed = { [self] in
            isRunning = false
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        service.readText(trimmed)
        isRunning = true
    }

    private func stop() {
        service.overlayController.dismiss()
        isRunning = false
    }
}

#Preview {
    ContentView()
}
