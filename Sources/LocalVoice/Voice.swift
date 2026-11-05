import Foundation

struct Voice: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let gender: String

    var summary: String { "\(language) · \(gender)" }

    static let all: [Voice] = [
        Voice(id: "af_heart", name: "Heart", language: "American", gender: "Female"),
        Voice(id: "af_bella", name: "Bella", language: "American", gender: "Female"),
        Voice(id: "am_michael", name: "Michael", language: "American", gender: "Male"),
        Voice(id: "am_fenrir", name: "Fenrir", language: "American", gender: "Male"),
        Voice(id: "bf_emma", name: "Emma", language: "British", gender: "Female"),
        Voice(id: "bm_george", name: "George", language: "British", gender: "Male"),
    ]
}

enum EnginePaths {
    static let fileManager = FileManager.default

    static var home: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LocalVoice", isDirectory: true)
    }

    static var python: URL {
        home.appendingPathComponent("engine/bin/python")
    }

    static var model: URL {
        home.appendingPathComponent("model/kokoro-v1_0.pth")
    }

    static var outputDirectory: URL {
        home.appendingPathComponent("wav", isDirectory: true)
    }

    static var isInstalled: Bool {
        fileManager.isExecutableFile(atPath: python.path)
            && fileManager.fileExists(atPath: model.path)
    }
}

enum EngineError: LocalizedError {
    case notInstalled
    case missingWorker
    case worker(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The speech engine is not installed yet."
        case .missingWorker:
            return "The bundled speech worker is missing. Rebuild the app."
        case .worker(let message):
            return message
        case .cancelled:
            return "Generation cancelled."
        }
    }
}
