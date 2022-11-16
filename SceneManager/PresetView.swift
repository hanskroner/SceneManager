//
//  PresetView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Models

struct PresetItem: Hashable, Codable {
    var name: String
    var systemImage: String
    var preset: deCONZLightState
    
    var color: Color {
        switch self.preset.colormode {
        case "ct":
            return Color(colorFromMired(mired: preset.ct!)!)
        case "xy":
            return Color(colorFromXY(point: CGPoint(x: preset.x!, y: preset.y!), brightness: 1.0))
        default:
            return Color(.black)
        }
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
        PresetView(presetItem: .constant(PresetItem(name: "Preset Item", systemImage: "lightbulb.2", preset:
                                            deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "xy", x: 0.2485, y: 0.0917))))
    }
}
