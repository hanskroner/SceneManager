//
//  PresetView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI
import UniformTypeIdentifiers

struct PresetScene: Hashable, Codable {
    var name: String
    var systemImage: String
    var preset: deCONZLightState
}

struct PresetView: View {
    @Binding var preset: PresetScene
    
    var body: some View {
        VStack {
            Label("", systemImage: preset.systemImage)
                .foregroundColor(.primary)
                .font(.system(size: 24))
            Text(preset.name)
                .font(.headline)
                .padding(.top, 4)
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
        .background(colorForPreset(preset: preset.preset))
        .cornerRadius(8)
        .itemProvider { preset.itemProvider }
    }
    
    func colorForPreset(preset: deCONZLightState) -> Color {
        switch preset.colormode {
        case "ct":
            return Color(colorFromMired(mired: preset.ct!)!)
        case "xy":
            return Color(colorFromXY(point: CGPoint(x: preset.x!, y: preset.y!), brightness: 1.0))
        default:
            return Color(.black)
        }
    }
}

extension PresetScene {
    static var draggableType = UTType(exportedAs: "com.hanskroner.SceneManager.presetScene")
    
    static func fromItemProviders(_ itemProviders: [NSItemProvider], completion: @escaping ([PresetScene]) -> Void) {
        let typeIdentifier = Self.draggableType.identifier
        let filteredProviders = itemProviders.filter {
            $0.hasItemConformingToTypeIdentifier(typeIdentifier)
        }
        
        let group = DispatchGroup()
        var result = [Int: PresetScene]()
        
        for (index, provider) in filteredProviders.enumerated() {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { (data, error) in
                defer { group.leave() }
                guard let data = data else { return }
                let decoder = JSONDecoder()
                guard let preset = try? decoder.decode(PresetScene.self, from: data)
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
