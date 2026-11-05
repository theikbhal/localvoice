import SwiftUI

@main
struct LocalVoiceApp: App {
    @StateObject private var controller = TTSController()

    var body: some Scene {
        WindowGroup("LocalVoice") {
            ContentView()
                .environmentObject(controller)
        }
        .defaultSize(width: 780, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
