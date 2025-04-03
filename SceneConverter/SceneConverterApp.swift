//
//  SceneConverterApp.swift
//  SceneConverter
//
//  Created by Hans Kröner on 03/04/2025.
//

import SwiftUI

@main
struct SceneConverterApp: App {
    var body: some Scene {
        Window("Scene Converter", id: "sceneconverter") {
            ContentView()
                .padding(16)
        }
        .windowResizability(.contentSize)
    }
}
