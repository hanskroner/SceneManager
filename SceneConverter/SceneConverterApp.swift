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
    
    private let _decoder = JSONDecoder()
    private let _encoder = JSONEncoder()
    
    private func models(fromURL url: URL) throws -> [CLIPScene] {
        struct CLIPWrapper: Decodable {
            let data: [CLIPScene]
        }
        
        let data = try Data(contentsOf: url)
        let wrapper = try _decoder.decode(CLIPWrapper.self, from: data)
        
        return wrapper.data
    }
    
    private func process(urls: [URL]) {
        for url in urls {
            // FIXME: Error handling
            let models = try! self.models(fromURL: url)
            for model in models {
                // FIXME: Error handling
                let preset = try! Preset(from: model)
                logger.info("\(preset.name, privacy: .public)")
                
                if let state = preset.state {
                    if let _ = state.on { logger.info("  on: \(state.on!, privacy: .public)") }
                    if let _ = state.bri { logger.info("  bri: \(state.bri!, privacy: .public)") }
                    if let _ = state.xy { logger.info("  xy: \(state.xy!, privacy: .public)") }
                    if let _ = state.ct { logger.info("  ct: \(state.ct!, privacy: .public)") }
                    logger.info("  transitiontime: \(state.transitiontime, privacy: .public)")
                }
                
                if let dynamics = preset.dynamics {
                    if let _ = dynamics.bri { logger.info("  bri: \(dynamics.bri!, privacy: .public)") }
                    if let _ = dynamics.xy { logger.info("  xy: \(dynamics.xy!, privacy: .public)") }
                    if let _ = dynamics.ct { logger.info("  ct: \(dynamics.ct!, privacy: .public)") }
                    logger.info("  effect_speed: \(dynamics.effect_speed, privacy: .public)")
                    logger.info("  auto_dynamic: \(dynamics.auto_dynamic, privacy: .public)")
                }
            }
        }
    }
    
    var body: some Scene {
        Window("Scene Converter", id: "sceneconverter") {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: .receivedURLsNotification)) { notification in
                    if let urls = notification.userInfo?["URLs"] as? [URL] {
                        DispatchQueue.main.async {
                            process(urls: urls)
                        }
                    }
                }
                .onDrop(of: ["public.json"], isTargeted: nil) { providers -> Bool in
                    var urls: [URL] = []
                    for itemProvider in providers {
                        itemProvider.loadItem(forTypeIdentifier: "public.json", options: nil) { (item, error) in
                            if let url = item as? URL {
                                urls.append(url)
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        process(urls: urls)
                    }
                    
                    return true
                }
                .padding(16)
        }
        .windowResizability(.contentSize)
    }
}
