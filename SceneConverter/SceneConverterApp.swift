//
//  SceneConverterApp.swift
//  SceneConverter
//
//  Created by Hans Kröner on 03/04/2025.
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.hanskroner.sceneconverter", category: "app")

extension Notification.Name {
    static let receivedURLsNotification = Notification.Name("ReceivedURLsNotification")
}
 
class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        
        NotificationCenter.default.post(name: .receivedURLsNotification, object: nil, userInfo: ["URLs": urls])
    }
}

@main
struct SceneConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Scene Converter", id: "sceneconverter") {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: .receivedURLsNotification)) { notification in
                    if let urls = notification.userInfo?["URLs"] as? [URL] {
                        for url in urls {
                            logger.info("\(url, privacy: .public)")
                        }
                    }
                }
                .onDrop(of: ["public.json"], isTargeted: nil) { providers -> Bool in
                    for itemProvider in providers {
                        itemProvider.loadItem(forTypeIdentifier: "public.json", options: nil) { (item, error) in
                            if let url = item as? URL {
                                logger.info("\(url, privacy: .public)")
                            }
                        }
                    }
                    
                    return true
                }
                .padding(16)
        }
        .windowResizability(.contentSize)
    }
}
