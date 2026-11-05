import AVFoundation
import AppKit
import Foundation

struct SynthesisRequest: Encodable {
    let id: Int
    let text: String
    let voice: String
    let speed: Double
    let out: String
}

private struct WorkerEvent: Decodable {
    let id: Int?
    let event: String
    let out: String?
    let duration: Double?
    let message: String?
}

private struct SynthesisResult {
    let url: URL
    let duration: Double
}

enum EngineState: Equatable {
    case idle
    case starting
    case warming
    case ready
    case working
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Starting"
        case .starting: return "Connecting"
        case .warming: return "Loading voice model"
        case .ready: return "Offline engine ready"
        case .working: return "Generating speech"
        case .failed: return "Engine unavailable"
        }
    }

    var isReady: Bool {
        self == .ready || self == .working
    }
}

@MainActor
final class TTSController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var text = "Welcome to LocalVoice. Type anything you like, choose a voice, and press Generate.\n\nEverything runs locally on your Mac. No cloud, no account, no cost."
    @Published var voice: Voice = Voice.all[0]
    @Published var speed: Double = 1.0
    @Published var state: EngineState = .idle
    @Published var isGenerating = false
    @Published var audioURL: URL?
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var playhead: Double = 0
    @Published var lastError: String?

    private var process: Process?
    private var inputPipe: Pipe?
    private var currentRequestID: Int?
    private var continuation: CheckedContinuation<SynthesisResult, Error>?
    private var logTail = ""
    private var stopping = false

    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?

    var engineInstalled: Bool { EnginePaths.isInstalled }

    func prepare() {
        guard state == .idle else { return }
        guard EnginePaths.isInstalled else {
            state = .failed("Run the engine installer to finish setup.")
            return
        }
        do {
            try ensureWorker()
            state = .starting
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func generate() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        isGenerating = true
        lastError = nil
        nextRequestID += 1
        let requestID = nextRequestID

        Task { @MainActor in
            do {
                try ensureWorker()
                try FileManager.default.createDirectory(
                    at: EnginePaths.outputDirectory, withIntermediateDirectories: true
                )
                let output = EnginePaths.outputDirectory
                    .appendingPathComponent("speech-\(requestID).wav")
                let request = SynthesisRequest(
                    id: requestID,
                    text: trimmed,
                    voice: voice.id,
                    speed: speed,
                    out: output.path
                )
                let result = try await send(request)
                audioURL = result.url
                duration = result.duration
                playhead = 0
                isGenerating = false
                state = .ready
                startPlayback()
            } catch is CancellationError {
                isGenerating = false
                state = .idle
            } catch {
                isGenerating = false
                lastError = error.localizedDescription
                state = EnginePaths.isInstalled ? .ready : .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        stopping = true
        currentRequestID = nil
        continuation?.resume(throwing: EngineError.cancelled)
        continuation = nil
        isGenerating = false
        state = .idle
        process?.terminate()
        process = nil
        inputPipe = nil
    }

    func togglePlayback() {
        guard let player else {
            startPlayback()
            return
        }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if playhead >= duration - 0.05 {
                player.currentTime = 0
            }
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to time: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(time, duration))
        playhead = player.currentTime
    }

    func saveAudio() {
        guard let audioURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "LocalVoice \(voice.name).wav"
        panel.title = "Save speech"
        if panel.runModal() == .OK, let destination = panel.url {
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.copyItem(at: audioURL, to: destination)
            } catch {
                lastError = "Could not save the file: \(error.localizedDescription)"
            }
        }
    }

    func revealAudio() {
        guard let audioURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([audioURL])
    }

    func openInstaller() {
        guard let script = Bundle.main.url(forResource: "setup_engine", withExtension: "sh") else {
            lastError = "Installer script not found in the app bundle."
            return
        }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [script],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                Task { @MainActor in
                    self.lastError = "Could not open Terminal: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Worker process

    private var nextRequestID = 0

    private func ensureWorker() throws {
        if let process, process.isRunning { return }
        guard EnginePaths.isInstalled else { throw EngineError.notInstalled }
        guard let worker = Bundle.main.url(forResource: "kokoro_worker", withExtension: "py") else {
            throw EngineError.missingWorker
        }

        stopping = false
        logTail = ""

        let process = Process()
        process.executableURL = EnginePaths.python
        process.arguments = [worker.path]

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"
        environment["HF_HUB_OFFLINE"] = "1"
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let lines = LineBuffer()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in lines.append(data) {
                guard let event = try? JSONDecoder().decode(WorkerEvent.self, from: Data(line.utf8)) else {
                    continue
                }
                Task { @MainActor [weak self] in self?.handle(event) }
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logTail.append(chunk)
                if self.logTail.count > 6_000 {
                    self.logTail = String(self.logTail.suffix(6_000))
                }
            }
        }

        process.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                self?.workerExited(status: finished.terminationStatus)
            }
        }

        try process.run()
        self.process = process
        self.inputPipe = stdin
        state = .starting
    }

    private func send(_ request: SynthesisRequest) async throws -> SynthesisResult {
        try await withCheckedThrowingContinuation { continuation in
            self.currentRequestID = request.id
            self.continuation = continuation
            state = .working

            do {
                let payload = try JSONEncoder().encode(request) + Data([0x0A])
                try inputPipe?.fileHandleForWriting.write(contentsOf: payload)
            } catch {
                self.continuation = nil
                self.currentRequestID = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func handle(_ event: WorkerEvent) {
        switch event.event {
        case "ready":
            state = .starting
        case "warm":
            if !isGenerating { state = .ready }
        case "done":
            guard event.id == currentRequestID,
                  let path = event.out,
                  let continuation else { return }
            self.continuation = nil
            currentRequestID = nil
            let url = URL(fileURLWithPath: path)
            continuation.resume(returning: SynthesisResult(
                url: url,
                duration: event.duration ?? audioDuration(at: url)
            ))
        case "error":
            if let continuation, event.id == nil || event.id == currentRequestID {
                self.continuation = nil
                currentRequestID = nil
                continuation.resume(throwing: EngineError.worker(event.message ?? "Unknown engine error."))
            }
        default:
            break
        }
    }

    private func workerExited(status: Int32) {
        process = nil
        inputPipe = nil
        if let continuation {
            self.continuation = nil
            currentRequestID = nil
            let detail = logTail.trimmingCharacters(in: .whitespacesAndNewlines)
            continuation.resume(throwing: EngineError.worker(
                detail.isEmpty ? "The speech engine stopped unexpectedly." : detail
            ))
        }
        if stopping {
            stopping = false
            state = .idle
        } else if !isGenerating {
            state = .failed("The speech engine stopped. Try again.")
        }
    }

    private func audioDuration(at url: URL) -> Double {
        (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
    }

    // MARK: - Playback

    private func startPlayback() {
        guard let audioURL else { return }
        playbackTimer?.invalidate()
        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            isPlaying = true
            playhead = 0
            if duration == 0 { duration = player.duration }
            startTimer()
        } catch {
            lastError = "Could not play the audio: \(error.localizedDescription)"
        }
    }

    private func startTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.playhead = player.currentTime
            }
        }
        RunLoop.main.add(playbackTimer!, forMode: .common)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.playhead = self.duration
            self.playbackTimer?.invalidate()
            self.playbackTimer = nil
        }
    }
}

private final class LineBuffer {
    private var buffer = Data()

    func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let index = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<index]
            buffer.removeSubrange(buffer.startIndex...index)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}
