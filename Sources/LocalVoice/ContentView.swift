import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var tts: TTSController
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 18) {
            header
            editor
            settings
            actions
            if tts.audioURL != nil {
                playerBar
            }
            footer
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.indigo)
        .task {
            tts.prepare()
            editorFocused = true
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(tts.lastError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("LocalVoice")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text("Free text to speech · private · runs on this Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(tts.state.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $tts.text)
                .font(.system(size: 15))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(12)

            if tts.text.isEmpty {
                Text("Type or paste English text…")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 220, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    editorFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.1),
                    lineWidth: 1
                )
        )
    }

    private var settings: some View {
        HStack(alignment: .bottom, spacing: 24) {
            field("VOICE") {
                Menu {
                    ForEach(Voice.all) { candidate in
                        Button {
                            tts.voice = candidate
                        } label: {
                            if candidate == tts.voice {
                                Label("\(candidate.name) — \(candidate.summary)", systemImage: "checkmark")
                            } else {
                                Text("\(candidate.name) — \(candidate.summary)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 9) {
                        voiceAvatar
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tts.voice.name)
                                .font(.callout.weight(.medium))
                            Text(tts.voice.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            field("SPEED") {
                HStack(spacing: 10) {
                    Slider(value: $tts.speed, in: 0.7...1.4, step: 0.05)
                        .frame(width: 180)
                    Text(String(format: "%.2fx", tts.speed))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }
                .padding(.bottom, 5)
            }

            Spacer()

            Text("\(tts.text.count) characters")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                tts.generate()
            } label: {
                Label(tts.isGenerating ? "Generating…" : "Generate", systemImage: "sparkles")
                    .frame(minWidth: 104)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!tts.state.isReady || tts.isGenerating || tts.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if tts.isGenerating {
                Button("Cancel") { tts.cancel() }
                    .controlSize(.large)
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button {
                tts.togglePlayback()
            } label: {
                Label(tts.isPlaying ? "Pause" : "Play",
                      systemImage: tts.isPlaying ? "pause.fill" : "play.fill")
            }
            .controlSize(.large)
            .disabled(tts.audioURL == nil)

            Button {
                tts.saveAudio()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .controlSize(.large)
            .disabled(tts.audioURL == nil)
        }
    }

    private var playerBar: some View {
        HStack(spacing: 12) {
            Button {
                tts.togglePlayback()
            } label: {
                Image(systemName: tts.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)

            Text(timeString(tts.playhead))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { tts.playhead },
                    set: { tts.seek(to: $0) }
                ),
                in: 0...max(tts.duration, 0.01)
            )

            Text(timeString(tts.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                tts.revealAudio()
            } label: {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show generated file in Finder")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
    }

    @ViewBuilder
    private var footer: some View {
        if !tts.engineInstalled {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speech engine is not installed")
                        .font(.callout.weight(.medium))
                    Text("One-time setup downloads about 350 MB and runs fully offline afterwards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Install Engine") { tts.openInstaller() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
            )
        } else {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("Private by design — your text and audio never leave this Mac.")
                Spacer()
                Text("Kokoro-82M · 24 kHz")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var voiceAvatar: some View {
        Text(String(tts.voice.name.prefix(1)))
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(avatarColor))
    }

    private var avatarColor: Color {
        switch tts.voice.gender {
        case "Female": return .pink
        default: return .indigo
        }
    }

    private var statusColor: Color {
        switch tts.state {
        case .ready: return .green
        case .working: return .orange
        case .starting, .warming: return .yellow
        case .failed: return .red
        case .idle: return .gray
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { tts.lastError != nil },
            set: { presented in
                if !presented { tts.lastError = nil }
            }
        )
    }

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
