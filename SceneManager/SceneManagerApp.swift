//
//  SceneManagerApp.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

@main
struct SceneManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
#if os(macOS)
        Settings {
            SettingsView()
        }
#endif
    }
}
