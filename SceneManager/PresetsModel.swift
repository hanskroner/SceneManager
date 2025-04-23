//
//  PresetsModel.swift
//  SceneManager
//
//  Created by Hans Kröner on 22/04/2025.
//

import Combine
import UniformTypeIdentifiers
import OSLog

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "preset-model")

public final class PresetsModel {
    private let _decoder = JSONDecoder()
    private let _encoder = JSONEncoder()
    
    // Combine Publishers
    let onPresetsUpdated = PassthroughSubject<[PresetItemGroup], Never>()
    
    private var _groups: [PresetItemGroup] = []
    
    var groups: [PresetItemGroup] {
        get { return _groups }
    }
    
    static let shared = PresetsModel()
    
    enum PresetFileError: Error {
        case noURLError(String)
    }
    
    private init() {
        _encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let documentsContents = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                
                // Copy sample presets if the Documents Directory is empty
                if documentsContents.isEmpty {
                    try copyFilesFromBundleToDocumentsDirectoryConformingTo(.json)
                }
                
                try self.loadPresetItems()
            }
        } catch DecodingError.typeMismatch(_, let context) {
            logger.error("\(context.debugDescription, privacy: .public)")
        } catch {
            logger.error("\(error, privacy: .public)")
        }
    }
    
    public func signalUpdate() {
        self.onPresetsUpdated.send(_groups)
    }
    
    // MARK: - Documents Directory Operations
    
    private func copyFilesFromBundleToDocumentsDirectoryConformingTo(_ fileType: UTType) throws {
        if let resPath = Bundle.main.resourcePath {
            let dirContents = try FileManager.default.contentsOfDirectory(atPath: resPath)
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            
            var filteredFiles = [String]()
            for (fileExtension) in fileType.tags[.filenameExtension] ?? [] {
                filteredFiles.append(contentsOf: dirContents.filter { $0.contains(fileExtension) })
            }
            
            for (fileName) in filteredFiles {
                if let documentsURL = documentsURL {
                    let sourceURL = URL(fileURLWithPath: Bundle.main.resourcePath!).appendingPathComponent(fileName, conformingTo: fileType)
                    let destURL = documentsURL.appendingPathComponent(fileName)
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
            }
        }
    }
    
    private func filesInDocumentsDirectoryConformingTo(_ fileType: UTType) throws -> [URL] {
        var fileURLs = [URL]()
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return fileURLs }
        
        // Add files for the Documents directory
        let dirContents = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        for (fileExtension) in fileType.tags[.filenameExtension] ?? [] {
            fileURLs.append(contentsOf: dirContents.filter{ $0.absoluteString.contains(fileExtension) })
        }
        
        // Add files for each sub directory in the Documents directory
        // This is quicker and simpler than performing deep enumeration using
        // a method like 'enumeratorAtURL'.
        let dirs = try dirContents.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false }
        for (dirURL) in dirs {
            let dirContents = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for (fileExtension) in fileType.tags[.filenameExtension] ?? [] {
                fileURLs.append(contentsOf: dirContents.filter{ $0.absoluteString.contains(fileExtension) })
            }
        }
        
        return fileURLs
    }
    
    // MARK: - File System Operations
    
    private func urlForPresetItem(_ presetItem: PresetItem) throws -> URL {
        // Create file name from Preset name
        let fileName = presetItem.name.lowercased().replacing(" ", with: "_").appending(".json")
        
        let url = presetItem.url?.deletingLastPathComponent().appendingPathComponent(fileName)
        
        // If the URL is nil, this PresetItem doesn't have a file representation.
        // Its URL would be the base 'Documents' directory with 'fileName' appended to it.
        if url == nil {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw PresetFileError.noURLError("Could not get URL for '\(presetItem.name)'")
            }
            
            return documentsURL.appendingPathComponent(fileName)
        }
        
        guard let url else {
            throw PresetFileError.noURLError("Could not get URL for '\(presetItem.name)'")
        }
        
        return url
    }
    
    private func loadPresetItemsFromDocumentsDirectory() throws -> [PresetItemGroup] {
        // Use a temporary Dictionary to store the Presets
        // Appending a PresetItem into the array that belongs to subdirectory
        // becomes a bit less of a hassle with Dictionaries
        var presetDirs: [String: [PresetItem]] = [:]
        
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        
        let presetFiles = try filesInDocumentsDirectoryConformingTo(.json)
        for (presetFile) in presetFiles {
            // Check if this preset file is in a subdirectory
            let subDir: String
            if (presetFile.deletingLastPathComponent().lastPathComponent != documentsURL.lastPathComponent) {
                subDir = presetFile.deletingLastPathComponent().lastPathComponent
            } else {
                subDir = "custom"
            }
            
            // Decode the preset file's contents and add them to Preset Dictionary
            let json = try String(contentsOf: presetFile, encoding: .utf8)
            let presetItem = try _decoder.decode(PresetItem.self, from: json.data(using: .utf8)!)
            presetItem.url = presetFile
            presetDirs[subDir, default: []].append(presetItem)
        }
        
        // Re-pack the dictionary into a sorted Array of PresetItemGroup
        // The presets in each group are also sorted. The 'custom' group
        // is included last, and as the first group.
        var presetGroups: [PresetItemGroup] = []
        let withoutCustom = presetDirs.filter { $0.key != "custom" }
        for (group, presets) in withoutCustom.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            presetGroups.append(PresetItemGroup(name: group,
                                                presets: presets.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })))
        }
        
        if let customGroup = presetDirs["custom"] {
            presetGroups.insert(PresetItemGroup(name: "custom",
                                                presets: customGroup.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })), at: 0)
        }
        
        return presetGroups
    }
    
    private func savePresetItemToDocumentsDirectory(_ presetItem: PresetItem) throws {
        let fileContents = try _encoder.encode(presetItem)
        let destURL = try urlForPresetItem(presetItem)
        try fileContents.write(to: destURL)
        
        presetItem.url = destURL
    }
    
    private func renamePresetItemInDocumentsDirectory(_ presetItem: PresetItem) throws {
      guard let file = presetItem.url else { return }
        
        let newFileURL = try urlForPresetItem(presetItem)
        var previousFileURL = file
        
        var resourceValues = URLResourceValues()
        resourceValues.name = newFileURL.lastPathComponent
        presetItem.url = newFileURL
        
        try previousFileURL.setResourceValues(resourceValues)
        try savePresetItemToDocumentsDirectory(presetItem)
    }
    
    private func deletePresetItemInDocumentsDirectory(_ presetItem: PresetItem) throws {
        guard let url = presetItem.url else {
            throw PresetFileError.noURLError("Could not get URL for '\(presetItem.name)'")
        }
        
        try FileManager.default.removeItem(at: url)
        
        // FIXME: Remove the directory if empty
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let subdirURL = url.deletingLastPathComponent()
        guard documentsURL != subdirURL else { return }
        
        // Add files for the Documents directory
        let dirContents = try FileManager.default.contentsOfDirectory(at: subdirURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        if dirContents.isEmpty {
            try FileManager.default.removeItem(at: subdirURL)
        }
    }
    
    // MARK: - Preset Item Operations
    
    func loadPresetItems() throws {
        self._groups = try loadPresetItemsFromDocumentsDirectory()
        
        signalUpdate()
    }
    
    func savePresetItem(_ presetItem: PresetItem) throws {
        try savePresetItemToDocumentsDirectory(presetItem)
        defer { signalUpdate() }
        
        // It's only possible to save 'PresetItem's into the 'custom' group
        if let customGroup = self._groups.filter({ $0.name == "custom" }).first {
            if let index = customGroup.presets.firstIndex(where: { $0.id == presetItem .id }) {
                customGroup.presets[index] = presetItem
            } else {
                customGroup.presets.append(presetItem)
                customGroup.presets.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
        }
    }
    
    func renamePresetItem(_ presetItem: PresetItem) throws {
        try renamePresetItemInDocumentsDirectory(presetItem)
        defer { signalUpdate() }
        
        // The passed-in PresetItem's name has already been updated by the UI,
        // but its UUID will remain the same until reloaded from the file system.
        // It's necessary to reload the renamed PresetItem from the filesystem to
        // get its updated UUID.
        for group in self._groups {
            if let index = group.presets.firstIndex(where: { $0.id == presetItem .id }) {
                // The cache's copy of 'preset' needs to update its UUID
                let json = try String(contentsOf: presetItem.url!, encoding: .utf8)
                let renamedPreset = try _decoder.decode(PresetItem.self, from: json.data(using: .utf8)!)
                renamedPreset.url = presetItem.url
                group.presets[index] = renamedPreset
                
                group.presets.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                return
            }
        }
    }
    
    func deletePresetItem(_ presetItem: PresetItem) throws {
        try deletePresetItemInDocumentsDirectory(presetItem)
        defer { signalUpdate() }
        
        // The passed-in PresetItem's name has already been updated by the UI,
        // but its UUID will remain the same until reloaded from the file system.
        for group in self._groups {
            for preset in group.presets {
                if preset.id == presetItem.id {
                    group.presets.removeAll(where: { $0.id == presetItem.id })
                    return
                }
            }
        }
    }
}
