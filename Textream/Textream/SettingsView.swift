//
//  SettingsView.swift
//  Textream
//
//  Created by Fatih Kadir Akın on 8.02.2026.
//

import SwiftUI
import AppKit
import Speech

// MARK: - Preview Panel Controller

class NotchPreviewController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotchPreviewContent>?

    func show(settings: NotchSettings) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY

        let maxWidth = NotchSettings.maxWidth
        let maxHeight = menuBarHeight + NotchSettings.maxHeight

        let xPosition = screenFrame.midX - maxWidth / 2
        let yPosition = screenFrame.maxY - maxHeight

        let content = NotchPreviewContent(settings: settings, menuBarHeight: menuBarHeight)
        let hostingView = NSHostingView(rootView: content)
        self.hostingView = hostingView

        let panel = NSPanel(
            contentRect: NSRect(x: xPosition, y: yPosition, width: maxWidth, height: maxHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView
        panel.orderFront(nil)
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }
}

struct NotchPreviewContent: View {
    @Bindable var settings: NotchSettings
    let menuBarHeight: CGFloat

    private static let loremWords = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua Ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur Excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium totam rem aperiam eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt".split(separator: " ").map(String.init)

    private let highlightedCount = 42

    var body: some View {
        GeometryReader { geo in
            let targetHeight = menuBarHeight + settings.textAreaHeight
            let currentWidth = settings.notchWidth

            ZStack(alignment: .top) {
                DynamicIslandShape(
                    topInset: 16,
                    bottomRadius: 18
                )
                .fill(.black)
                .frame(width: currentWidth, height: targetHeight)

                VStack(spacing: 0) {
                    Spacer().frame(height: menuBarHeight)

                    SpeechScrollView(
                        words: Self.loremWords,
                        highlightedCharCount: highlightedCount,
                        font: settings.font,
                        highlightColor: settings.fontColorPreset.color,
                        isListening: false
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .frame(width: currentWidth, height: targetHeight)
            }
            .frame(width: currentWidth, height: targetHeight, alignment: .top)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .animation(.easeInOut(duration: 0.15), value: settings.notchWidth)
            .animation(.easeInOut(duration: 0.15), value: settings.textAreaHeight)
        }
    }
}

// MARK: - Settings Tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, fontSize, fontColor, overlayMode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .fontSize: return "Font Size"
        case .fontColor: return "Color"
        case .overlayMode: return "Overlay"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .fontSize: return "textformat.size"
        case .fontColor: return "paintpalette"
        case .overlayMode: return "macwindow"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Bindable var settings: NotchSettings
    @Environment(\.dismiss) private var dismiss
    @State private var previewController = NotchPreviewController()
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)

                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 16)
                            Text(tab.label)
                                .font(.system(size: 13, weight: .regular))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("Reset") {
                    settings.notchWidth = NotchSettings.defaultWidth
                    settings.textAreaHeight = NotchSettings.defaultHeight
                    settings.fontSizePreset = .lg
                    settings.fontColorPreset = .white
                    settings.overlayMode = .pinned
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(width: 120)
            .frame(maxHeight: .infinity)
            .background(Color.primary.opacity(0.04))

            Divider()

            // Content
            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .general:
                        generalTab
                    case .fontSize:
                        fontSizeTab
                    case .fontColor:
                        fontColorTab
                    case .overlayMode:
                        overlayModeTab
                    }
                }
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .top)

                Divider()

                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 500, height: 280)
        .background(.ultraThinMaterial)
        .onAppear {
            previewController.show(settings: settings)
        }
        .onDisappear {
            previewController.dismiss()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(spacing: 14) {
            // Width slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Width")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(Int(settings.notchWidth))px")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $settings.notchWidth,
                    in: NotchSettings.minWidth...NotchSettings.maxWidth,
                    step: 10
                )
            }

            // Height slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Height")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(Int(settings.textAreaHeight))px")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $settings.textAreaHeight,
                    in: NotchSettings.minHeight...NotchSettings.maxHeight,
                    step: 10
                )
            }

            // Language picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Speech Language")
                    .font(.system(size: 13, weight: .medium))
                Picker("", selection: $settings.speechLocale) {
                    ForEach(SFSpeechRecognizer.supportedLocales().sorted(by: { $0.identifier < $1.identifier }), id: \.identifier) { locale in
                        Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier)
                    }
                }
                .labelsHidden()
            }
        }
    }

    // MARK: - Font Size Tab

    private var fontSizeTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text Size")
                .font(.system(size: 13, weight: .medium))

            HStack(spacing: 8) {
                ForEach(FontSizePreset.allCases) { preset in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.fontSizePreset = preset
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text("Ag")
                                .font(.system(size: preset.pointSize * 0.7, weight: .semibold))
                                .foregroundStyle(settings.fontSizePreset == preset ? Color.accentColor : .primary)
                            Text(preset.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(settings.fontSizePreset == preset ? Color.accentColor : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(settings.fontSizePreset == preset ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(settings.fontSizePreset == preset ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Font Color Tab

    private var fontColorTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlight Color")
                .font(.system(size: 13, weight: .medium))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(FontColorPreset.allCases) { preset in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.fontColorPreset = preset
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                                )
                                .overlay(
                                    settings.fontColorPreset == preset
                                        ? Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(preset == .white ? .black : .white)
                                        : nil
                                )
                            Text(preset.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(settings.fontColorPreset == preset ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(settings.fontColorPreset == preset ? preset.color.opacity(0.1) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(settings.fontColorPreset == preset ? preset.color.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Overlay Mode Tab

    private var overlayModeTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overlay Mode")
                .font(.system(size: 13, weight: .medium))

            VStack(spacing: 8) {
                ForEach(OverlayMode.allCases) { mode in
                    Button {
                        settings.overlayMode = mode
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(settings.overlayMode == mode ? Color.accentColor : .secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(settings.overlayMode == mode ? Color.accentColor : .primary)
                                Text(mode.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if settings.overlayMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(settings.overlayMode == mode ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(settings.overlayMode == mode ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
