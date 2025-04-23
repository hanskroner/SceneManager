//
//  SceneManagerApp.swift
//  SceneManager
//
//  Created by Hans Kröner on 08/10/2023.
//

import SwiftUI
import AppKit
import OSLog
import deCONZ

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "app")

@main
struct SceneManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @Environment(\.openWindow) private var openWindow
    
    var body: some SwiftUI.Scene {
        WindowGroup(for: UUID.self) { _ in
            ContentView()
        }
        .commands {
            deCONZCommandMenu()
            
            LightsCommandMenu()
            
            CommandGroup(after: .singleWindowList) {
                Button("Activity") {
                    openWindow(id: "activity")
                }.keyboardShortcut("0", modifiers: [.command, .option])
            }
        }
        
        UtilityWindow("Activity", id: "activity") {
            Activity()
        }
        .commandsRemoved()
        
#if os(macOS)
        Settings {
            // TODO: Won't work with WindowGroup
            SettingsView()
//                .environment(window)
        }
#endif
    }
}

struct deCONZCommandMenu: Commands {
    @FocusedValue(\.activeWindow) var activeWindow
    
    var body: some Commands {
        CommandMenu("deCONZ") {
            Button("Reload") {
                Task {
                    try await RESTModel.shared.refreshCache()
                }
            }.keyboardShortcut("r", modifiers: .command)
            
            Divider()
            
            Button("Delete Phoscon Keys…") {
                guard let activeWindow else { return }
                
                Task {
                    let allKeys = try await RESTModel.shared.allAPIKeys()
                    activeWindow.phosconKeys = allKeys.filter({ $0.name.hasPrefix("Phoscon#") }).map({ $0.key })
                    
                    // FIXME: Don't show if 'count' is 0
                    //        Instead, show a dialog saying there are not Phoscon Keys.
                    activeWindow.isPresentingPhosconDelete = true
                }
            }
        }
    }
}

struct LightsCommandMenu: Commands {
    @FocusedValue(\.activeWindow) var activeWindow
    
    var body: some Commands {
        CommandMenu("Lights") {
            Button("Configure Startup Values…") {
                guard let activeWindow else { return }
                
                activeWindow.isPresentingStartupConfiguration = true
            }.keyboardShortcut("s", modifiers: .command)
        }
    }
}
