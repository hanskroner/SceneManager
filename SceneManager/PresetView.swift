//
//  PresetView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Models

struct PresetItem: Hashable {
    var name: String
    var systemImage: String
    var preset: deCONZLightState
    
    var color: Color {
        switch self.preset.colormode {
        case .ct(let ct):
            return Color(colorFromMired(mired: ct)!)
        case .xy(let x, let y):
            return Color(colorFromXY(point: CGPoint(x: x, y: y), brightness: 1.0))
        }
    }
}

extension PresetItem: Codable {
    enum CodingKeys: CodingKey {
        case name, image, state
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        systemImage = try container.decode(String.self, forKey: .image)
        preset = try container.decode(deCONZLightState.self, forKey: .state)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(systemImage, forKey: .image)
        try container.encode(preset, forKey: .state)
    }
}

extension PresetItem {
    static var draggableType = UTType(exportedAs: "com.hanskroner.scene-manager.preset-item")
    
    static func fromItemProviders(_ itemProviders: [NSItemProvider], completion: @escaping ([PresetItem]) -> Void) {
        let typeIdentifier = Self.draggableType.identifier
        let filteredProviders = itemProviders.filter {
            $0.hasItemConformingToTypeIdentifier(typeIdentifier)
        }
        
        let group = DispatchGroup()
        var result = [Int: PresetItem]()
        
        for (index, provider) in filteredProviders.enumerated() {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { (data, error) in
                defer { group.leave() }
                guard let data = data else { return }
                let decoder = JSONDecoder()
                guard let preset = try? decoder.decode(PresetItem.self, from: data)
                else { return }
                result[index] = preset
            }
        }
        
        group.notify(queue: .global(qos: .userInitiated)) {
            let presets = result.keys.sorted().compactMap { result[$0] }
            DispatchQueue.main.async {
                completion(presets)
            }
        }
    }
    
    var itemProvider: NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.draggableType.identifier, visibility: .all) {
            let encoder = JSONEncoder()
            do {
                let data = try encoder.encode(self)
                $0(data, nil)
            } catch {
                $0(nil, error)
            }
            return nil
        }
        return provider
    }
}

// MARK: - Views

struct PresetView: View {
    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    @State private var presets = [PresetItem]()
    
    var body: some View {
        List {
            Section("Scene Presets") {
                ForEach($presets, id: \.self) { preset in
                    PresetItemView(presetItem: preset)
                }
            }
        }
        .task {
            Task {
                if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let documentsContents = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                    
                    if documentsContents.isEmpty {
                        try deconzModel.copyFilesFromBundleToDocumentsDirectoryConformingTo(.json)
                    }
                    
                    presets = try deconzModel.loadPresetItemsFromDocumentsDirectory()
                }
            }
        }
    }
}

struct PresetItemView: View {
    @Binding var presetItem: PresetItem
    
    var body: some View {
        VStack {
            Label("", systemImage: presetItem.systemImage)
                .foregroundColor(.primary)
                .font(.system(size: 24))
            Text(presetItem.name)
                .font(.headline)
                .padding(.top, 4)
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
        .background(presetItem.color)
        .cornerRadius(8)
        .itemProvider { presetItem.itemProvider }
    }
}

// MARK: - Previews

struct PresetView_Previews: PreviewProvider {
    static var previews: some View {
        PresetView()
    }
}
