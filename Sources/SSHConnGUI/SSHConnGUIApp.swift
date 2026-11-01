import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // При запуске из терминала (swift run) процесс не является бандлом:
        // без этого окно не получает фокус и иконку в Dock.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct SSHConnGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = HostListModel()

    var body: some Scene {
        Window("ssh-conn", id: "main") {
            HostListView(model: model)
        }
        .defaultSize(width: 860, height: 480)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Обновить список") { model.reload() }
                    .keyboardShortcut("r")
            }
        }
    }
}
