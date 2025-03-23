//
//  Presets.swift
//  SceneManager
//
//  Created by Hans Kröner on 20/10/2023.
//

import SwiftUI
import UniformTypeIdentifiers
import OSLog
import deCONZ

// MARK: - Presets Model

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "presets")

@Observable
class Presets {
    var items: [PresetItem] = [PresetItem]()
    
    var scrollToPresetItemID: UUID? = nil
    
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    init() {
        // Pretty-print JSON output
        encoder.outputFormatting = .prettyPrinted
        
        do {
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let documentsContents = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                
                if documentsContents.isEmpty {
                    try copyFilesFromBundleToDocumentsDirectoryConformingTo(.json)
                }
                
                self.items = try loadPresetItemsFromDocumentsDirectory()
            }
        } catch DecodingError.typeMismatch(_, let context) {
            logger.error("\(context.debugDescription, privacy: .public)")
        } catch {
            logger.error("\(error, privacy: .public)")
        }
    }
    
    func copyFilesFromBundleToDocumentsDirectoryConformingTo(_ fileType: UTType) throws {
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
        let dirContents = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        
        for (fileExtension) in fileType.tags[.filenameExtension] ?? [] {
            fileURLs.append(contentsOf: dirContents.filter{ $0.absoluteString.contains(fileExtension) })
        }
        
        return fileURLs
    }
    
    enum PresetFileError: Error {
        case noURLError(String)
    }
    
    private func urlForPresetItem(_ presetItem: PresetItem) throws -> URL {
        // Create file name from Preset name
        let fileName = presetItem.name.lowercased().replacing(" ", with: "_").appending(".json")
        
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw PresetFileError.noURLError("Could not get URL for '\(presetItem.name)'")
        }
        
        let url = documentsURL.appendingPathComponent(fileName)
        
        return url
    }
    
    func loadPresetItemsFromDocumentsDirectory() throws -> [PresetItem] {
        var presets = [PresetItem]()
        
        let presetFiles = try filesInDocumentsDirectoryConformingTo(.json)
        for (presetFile) in presetFiles {
            let json = try String(contentsOf: presetFile, encoding: .utf8)
            let presetItem = try decoder.decode(PresetItem.self, from: json.data(using: .utf8)!)
            presetItem.filename = presetFile.lastPathComponent
            presets.append(presetItem)
        }
        
        return presets.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    
    func savePresetItemToDocumentsDirectory(_ presetItem: PresetItem) throws {
        let fileContents = try encoder.encode(presetItem)
        let destURL = try urlForPresetItem(presetItem)
        try fileContents.write(to: destURL)
    }
    
    func renamePresetItemInDocumentsDirectory(_ presetItem: PresetItem) throws {
      guard let filename = presetItem.filename else { return }
        
        let newFileURL = try urlForPresetItem(presetItem)
        var previousFileURL = newFileURL.deletingLastPathComponent().appending(component: filename)
        
        var resourceValues = URLResourceValues()
        resourceValues.name = newFileURL.lastPathComponent
        presetItem.filename = newFileURL.lastPathComponent
        
        try previousFileURL.setResourceValues(resourceValues)
        try savePresetItemToDocumentsDirectory(presetItem)
    }
    
    func deletePresetItemInDocumentsDirectory(_ presetItem: PresetItem) throws {
        let url = try urlForPresetItem(presetItem)
        try FileManager.default.removeItem(at: url)
    }
}

// MARK: - PresetItem Model

@Observable
class PresetItem: Identifiable, Codable, Transferable {
    let id: UUID = UUID()
    
    var name: String
    var systemImage: String
    var state: JSON
    
    var filename: String? = nil
    
    var isRenaming: Bool = false
    
    var color: Color {
        // FIXME: This was nicer when there was a specific type instead of 'JSON'
        switch self.state["colormode"]!.stringValue {
        case "ct":
            return Color(SceneManager.color(fromMired: self.state["ct"]!.intValue!)!)
        case "xy":
            let xy = self.state["xy"]!
            return Color(SceneManager.color(fromXY: CGPoint(x: xy[0]!.doubleValue!, y: xy[1]!.doubleValue!), brightness: 0.5))
            
        default:
            return .white
        }
//        switch self.state.colormode {
//        case .ct(let ct):
//            return Color(SceneManager.color(fromMired: ct)!)
//        case .xy(let x, let y):
//            return Color(SceneManager.color(fromXY: CGPoint(x: x, y: y), brightness: 0.5))
//        }
    }
    
    enum CodingKeys: CodingKey {
        case name, image, state
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        systemImage = try container.decode(String.self, forKey: .image)
        state = try container.decode(JSON.self, forKey: .state)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(name, forKey: .name)
        try container.encode(systemImage, forKey: .image)
        try container.encode(state, forKey: .state)
    }
    
    static var transferRepresentation: some TransferRepresentation {
            CodableRepresentation(contentType: .presetItem)
        }
}

extension UTType {
    static var presetItem = UTType(exportedAs: "com.hanskroner.scenemanager.preset-item")
}

//extension PresetItem {
//    static var draggableType = UTType(exportedAs: "com.hanskroner.scenemanager.preset-item")
//    
//    static func fromItemProviders(_ itemProviders: [NSItemProvider], completion: @escaping ([PresetItem]) -> Void) {
//        let typeIdentifier = Self.draggableType.identifier
//        let filteredProviders = itemProviders.filter {
//            $0.hasItemConformingToTypeIdentifier(typeIdentifier)
//        }
//        
//        let group = DispatchGroup()
//        var result = [Int: PresetItem]()
//        
//        for (index, provider) in filteredProviders.enumerated() {
//            group.enter()
//            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { (data, error) in
//                defer { group.leave() }
//                guard let data = data else { return }
//                let decoder = JSONDecoder()
//                guard let preset = try? decoder.decode(PresetItem.self, from: data)
//                else { return }
//                result[index] = preset
//            }
//        }
//        
//        group.notify(queue: .global(qos: .userInitiated)) {
//            let presets = result.keys.sorted().compactMap { result[$0] }
//            DispatchQueue.main.async {
//                completion(presets)
//            }
//        }
//    }
//    
//    var itemProvider: NSItemProvider {
//        let provider = NSItemProvider()
//        provider.registerDataRepresentation(forTypeIdentifier: Self.draggableType.identifier, visibility: .all) {
//            let encoder = JSONEncoder()
//            do {
//                let data = try encoder.encode(self)
//                $0(data, nil)
//            } catch {
//                $0(nil, error)
//            }
//            return nil
//        }
//        return provider
//    }
//}

// MARK: - Presets View

struct PresetsView: View {
    @Environment(Presets.self) private var presets
    
    var body: some View {
        @Bindable var presets = presets
        
        ScrollViewReader { scrollReader in
            List {
                Section("Scene Presets") {
                    ForEach($presets.items, id: \.id) { $item in
                        PresetItemView(presetItem: $item)
                    }
                }
            }
            .onChange(of: presets.scrollToPresetItemID) { previousItem, newItem in
                if let item = newItem {
                    withAnimation {
                        scrollReader.scrollTo(item, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - PresetItem View

struct PresetItemView: View {
    @Environment(Presets.self) private var presets
    
    @Binding var presetItem: PresetItem
    
    @State private var isPresentingConfirmation: Bool = false
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack {
            Label("", systemImage: presetItem.systemImage)
                .foregroundColor(isDark(presetItem.color) ? .white : Color(NSColor.windowBackgroundColor))
                .font(.system(size: 24))
            if (presetItem.isRenaming) {
                TextField("", text: $presetItem.name)
                    .id(presetItem.id)
                    .multilineTextAlignment(.center)
                    .font(.headline)
                    .padding([.leading, .trailing], 12)
                    .padding(.top, 4)
                    .focused($isFocused)
                    .onChange(of: isFocused) {
                        // Only act when focus is lost by the TextField the rename is happening in
                        guard isFocused == false else { return }
                        
                        // Do this first to force SwiftUI to recompute the view
                        presetItem.isRenaming = false
                        
                        do {
                            try presets.renamePresetItemInDocumentsDirectory(presetItem)
                        } catch {
                            logger.error("\(error, privacy: .public)")
                        }
                        
                        withAnimation {
                            presets.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                        }
                    }
                    .onAppear {
                        isFocused = true
                    }
            } else {
                Text(presetItem.name)
                    .id(presetItem.id)
                    .foregroundColor(isDark(presetItem.color) ? .white : Color(NSColor.windowBackgroundColor))
                    .font(.headline)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
        .background(presetItem.color)
        .cornerRadius(8)
//        .itemProvider { presetItem.itemProvider }
        .draggable(presetItem)
        .contextMenu {
            Button(action: {
                presetItem.isRenaming = true
            }, label: {
                Text("Rename Preset")
            })
            
            Button(action: {
                isPresentingConfirmation = true
            }, label: {
                Text("Delete Preset")
            })
        }
        .confirmationDialog("Are you sure you want to delete '\(presetItem.name)'?", isPresented: $isPresentingConfirmation) {
            Button("Delete Preset", role: .destructive) {
                deletePresetItem(presetItem)
            }
        }
    }
    
    func deletePresetItem(_ presetItem: PresetItem) {
        do {
            try presets.deletePresetItemInDocumentsDirectory(presetItem)
        } catch {
            logger.error("\(error, privacy: .public)")
        }
        
        withAnimation {
            presets.items.removeAll(where: { $0.id == presetItem.id })
        }
    }
    
    func isDark(_ color: Color) -> Bool {
        var r, g, b, a: CGFloat
        (r, g, b, a) = (0, 0, 0, 0)
        NSColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return  lum < 0.77
    }
}

// MARK: - Previews

#Preview("Presets") {
        let contentURL = Bundle.main.url(forResource: "Presets", withExtension: "json")
        let contentData = try! Data(contentsOf: contentURL!)
        let presets = Presets(json: contentData)
        
        return PresetsView()
            .frame(width: 200, height: 420, alignment: .center)
            .environment(presets)
    
}
