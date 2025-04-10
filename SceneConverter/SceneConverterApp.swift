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

private struct PresetFileData: Codable {
    let file: String
    let preset: Preset
}

@main
struct SceneConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    private let _decoder = JSONDecoder()
    private let _encoder = JSONEncoder()
    
    @State private var writeQueue: [String: [PresetFileData]] = [:]
    @State private var isExporting: Bool = false
    
    func showSavePanel() -> URL? {
        let savePanel = NSOpenPanel()
        savePanel.allowedContentTypes = [.directory]
        savePanel.canChooseFiles = false
        savePanel.canChooseDirectories = true
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.allowsOtherFileTypes = false
        savePanel.prompt = "Export"
        
        let response = savePanel.runModal()
        return response == .OK ? savePanel.url : nil
    }
    
    private func models(fromURL url: URL) throws -> [CLIPScene] {
        struct CLIPWrapper: Decodable {
            let data: [CLIPScene]
        }
        
        let data = try Data(contentsOf: url)
        let wrapper = try _decoder.decode(CLIPWrapper.self, from: data)
        
        return wrapper.data
    }
    
    private func process(urls: [URL]) {
        // Clear the write queue
        writeQueue.removeAll()
        
        for url in urls {
            var fileData: [PresetFileData] = []
            let dir = url.lastPathComponent.components(separatedBy: ".").first ?? url.lastPathComponent
            
            do {
                let models = try self.models(fromURL: url)
                for model in models {
                    let preset = try Preset(from: model)
                    let file = preset.name.lowercased().replacingOccurrences(of: " ", with: "_") + ".json"
                    
                    fileData.append(PresetFileData(file: file, preset: preset))
                }
            } catch {
                // FIXME: Error handling
                logger.error("\(error, privacy: .public)")
                return
            }
            
            writeQueue[dir] = fileData
        }
        
        // Show the "save" dialog
        self.isExporting = true
    }
    
    var body: some Scene {
        Window("Scene Converter", id: "sceneconverter") {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: .receivedURLsNotification)) { notification in
                    if let urls = notification.userInfo?["URLs"] as? [URL] {
                        process(urls: urls)
                    }
                }
                .onDrop(of: ["public.json"], isTargeted: nil) { providers -> Bool in
                    Task {
                        var urls: [URL] = []
                        for itemProvider in providers {
                            if let url = try? await itemProvider.loadItem(forTypeIdentifier: "public.json") as? URL {
                                urls.append(url)
                            }
                        }
                        
                        process(urls: urls)
                    }
                    
                    return true
                }
                .onChange(of: isExporting) { oldValue, newValue in
                    // Pretty-print JSON output
                    _encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    
                    guard newValue, newValue == true else { return }
                    // Even though this is exporting files, a File Importer is used to select
                    // the directory where the exported files will be saved. Would be nice to
                    // be able to customize the dialog to make the "Open" button reflect this.
                    guard let saveURL = showSavePanel() else { return }
                    
                    for (directory, fileData) in writeQueue {
                        // Create the directory that will hold the scene .json files
                        do {
                            try FileManager.default.createDirectory(at: saveURL.appendingPathComponent(directory), withIntermediateDirectories: false)
                            
                            // Export the scene .json files to the new directory
                            for data in fileData {
                                let fileContents = try _encoder.encode(data.preset)
                                try fileContents.write(to: saveURL.appendingPathComponent(directory).appendingPathComponent(data.file))
                            }
                        } catch {
                            // FIXME: Error handling
                            logger.error("\(error, privacy: .public)")
                            return
                        }
                    }
                    
                    self.isExporting = false
                }
                // .fileImporter cannot be customized in the same way NSOpenPanel
                //.fileImporter(isPresented: $isExporting, allowedContentTypes: [.directory]) { result in
                //}
                .padding(16)
        }
        .windowResizability(.contentSize)
    }
}
