import AppKit
import SwiftUI
import DiarizeCore

@main
struct DiarizeAppMain: App {
    @StateObject private var library = LibraryViewModel()

    init() {
        // SwiftPM executables default to background-tool (no Dock icon, no window focus).
        // Promote to a foreground app so the window appears and gets focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

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
                Button("Open Recording …") { library.openImportDialog() }
                    .keyboardShortcut("o")
                Button("Reload Library") { library.reload() }
                    .keyboardShortcut("r")
            }
        }
    }
}
