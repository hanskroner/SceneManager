//
//  SceneManagerApp.swift
//  SceneManager
//
//  Created by Hans Kröner on 08/10/2023.
//

import SwiftUI
import deCONZ

@main
struct SceneManagerApp: App {
    @State private var sidebar = Sidebar()
    @State private var lights = Lights()
    @State private var presets = Presets()
    
    @State private var window = WindowItem()
    
    var body: some SwiftUI.Scene {
        // FIXME: Independent instances of environment objects per-window seems complicated with SwiftUI
        //        Use 'Window' instead of 'WindowGroup' - which won't allow the app to have multiple windows.
        Window("Scene Manager", id: "scenemanager") {
            ContentView()
                .environment(window)
                .environment(sidebar)
                .environment(lights)
                .environment(presets)
                .task {
                    do {
                        window.sidebar = sidebar
                        window.lights = lights
                        
                        try await RESTModel.shared.refreshCache()
                    } catch {
                        print(error)
                    }
                }
        }
        
#if os(macOS)
        Settings {
            SettingsView()
        }
#endif
    }
}
