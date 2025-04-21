//
//  SceneManagerApp.swift
//  SceneManager
//
//  Created by Hans Kröner on 08/10/2023.
//

import SwiftUI
import OSLog
import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "app")

extension Task where Failure == Never, Success == Void {
    @discardableResult init(priority: TaskPriority? = nil, operation: @escaping () async throws -> Void, `catch`: @escaping (Error) -> Void) {
        self.init(priority: priority) {
            do {
                _ = try await operation()
            } catch {
                `catch`(error)
            }
        }
    }
}

@main
struct SceneManagerApp: App {
    @State private var sidebar = Sidebar()
    @State private var lights = Lights()
    @State private var presets = Presets()
    
    @State private var window = WindowItem()
    
    @State private var isPresentingStartupConfiguration = false
    
    @State private var isPresentingPhosconDelete = false
    @State private var phosconKeys: [String] = []
    
    @Environment(\.openWindow) private var openWindow
    
    var body: some SwiftUI.Scene {
        // TODO: Independent instances of environment objects per-window seems complicated with SwiftUI
        //        Use 'Window' instead of 'WindowGroup' - which won't allow the app to have multiple windows.
        Window("Scene Manager", id: "scenemanager") {
            ContentView()
                .environment(window)
                .environment(sidebar)
                .environment(lights)
                .environment(presets)
                .sheet(isPresented: $isPresentingStartupConfiguration) {
                    LightConfigurationView()
                        .environment(window)
                        .frame(width: 680)
                        .padding(12)
                }
                .confirmationDialog("Are you sure you want to delete \(phosconKeys.count) Phoscon keys?", isPresented: $isPresentingPhosconDelete) {
                    Button("Delete \(phosconKeys.count) Keys", role: .destructive) {
                        // Call on the REST API to perform deletion
                        window.clearWarnings()
                        Task {
                            for key in phosconKeys {
                                try await RESTModel.shared.deleteAPIKey(key: key)
                            }
                        } catch: { error in
                            logger.error("\(error, privacy: .public)")
                            
                            window.handleError(error)
                        }
                    }
                }
                .task {
                    window.clearWarnings()
                    do {
                        window.sidebar = sidebar
                        window.lights = lights
                        
                        try await RESTModel.shared.refreshCache()
                    } catch {
                        logger.error("\(error, privacy: .public)")
                        
                        window.handleError(error)
                    }
                }
        }
        .commands {
            CommandMenu("deCONZ") {
                Button("Reload") {
                    Task {
                        try await RESTModel.shared.refreshCache()
                    }
                }.keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Button("Delete Phoscon Keys…") {
                    Task {
                        let allKeys = try await RESTModel.shared.allAPIKeys()
                        phosconKeys = allKeys.filter({ $0.name.hasPrefix("Phoscon#") }).map({ $0.key })
                        
                        isPresentingPhosconDelete = true
                    }
                }
            }
            
            CommandMenu("Lights") {
                Button("Configure Startup Values…") {
                    isPresentingStartupConfiguration = true
                }.keyboardShortcut("s", modifiers: .command)
            }
            
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
                .environment(window)
        }
#endif
    }
}
