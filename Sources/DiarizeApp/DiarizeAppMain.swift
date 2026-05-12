import SwiftUI
import DiarizeCore

@main
struct DiarizeAppMain: App {
    @StateObject private var library = LibraryViewModel()

    var body: some Scene {
        WindowGroup("diarize") {
            RootView()
                .environmentObject(library)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Aufnahme öffnen …") { library.openImportDialog() }
                    .keyboardShortcut("o")
                Button("Bibliothek neu laden") { library.reload() }
                    .keyboardShortcut("r")
            }
        }
    }
}
