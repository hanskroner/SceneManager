//
//  SceneManagerApp.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

@main
struct SceneManagerApp: App {
    @StateObject private var deconzModel = deCONZClientModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deconzModel)
        }
        
#if os(macOS)
        Settings {
            SettingsView()
        }
#endif
    }
}
