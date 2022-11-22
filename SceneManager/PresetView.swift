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
    var state: deCONZLightState
    
    var isRenaming: Bool = false
    var wantsFocus: Bool = false
    
    var color: Color {
        switch self.state.colormode {
        case .ct(let ct):
            return Color(SceneManager.color(fromMired: ct)!)
        case .xy(let x, let y):
            return Color(SceneManager.color(fromXY: CGPoint(x: x, y: y)))
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
        state = try container.decode(deCONZLightState.self, forKey: .state)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(systemImage, forKey: .image)
        try container.encode(state, forKey: .state)
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
    
    var body: some View {
        ScrollViewReader { scrollReader in
            List {
                Section("Scene Presets") {
                    ForEach($deconzModel.presets, id: \.name) { preset in
                        PresetItemView(presetItem: preset)
                    }
                }
            }
            .onChange(of: deconzModel.scrollToPresetItemID) { item in
                if let item = item {
                    withAnimation {
                        scrollReader.scrollTo(item, anchor: .center)
                    }
                }
            }
        }
    }
}

struct PresetItemView: View {
    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    @Binding var presetItem: PresetItem
    
    @State var newName = ""
    @State var isPresentingConfirmation: Bool = false
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack {
            Label("", systemImage: presetItem.systemImage)
                .foregroundColor(isDark(presetItem.color) ? .white : Color(NSColor.darkGray))
                .font(.system(size: 24))
            if (presetItem.isRenaming) {
                TextField("", text: $newName)
                    .multilineTextAlignment(.center)
                    .font(.headline)
                    .padding(.leading, 4)
                    .padding(.trailing, 12)
                    .padding(.top, 4)
                    .focused($isFocused)
                    .onChange(of: isFocused) { newValue in
                        if newValue == false {
                            do {
                                try deconzModel.renamePresetItemInDocumentsDirectory(presetItem, newName: newName)
                                presetItem.name = newName
                                presetItem.isRenaming = false
                            } catch {
                                print(error)
                            }
                        }
                    }
                    .onAppear {
                        newName = presetItem.name
                        isFocused = presetItem.wantsFocus
                    }
            } else {
                Text(presetItem.name)
                    .foregroundColor(isDark(presetItem.color) ? .white : Color(NSColor.darkGray))
                    .font(.headline)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
        .background(presetItem.color)
        .cornerRadius(8)
        .itemProvider { presetItem.itemProvider }
        .contextMenu {
            Button(action: {
                presetItem.isRenaming = true
                presetItem.wantsFocus = true
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
                try deconzModel.deletePresetItemInDocumentsDirectory(presetItem)
            } catch {
                print(error)
            }
        
        withAnimation {
            deconzModel.presets.removeAll(where: { $0.name == presetItem.name })
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

struct PresetView_Previews: PreviewProvider {
    static var previews: some View {
        PresetView()
    }
}
