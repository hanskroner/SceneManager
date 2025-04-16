//
//  Lights.swift
//  SceneManager
//
//  Created by Hans Kröner on 21/10/2023.
//

import SwiftUI
import OSLog
import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "lights")

// MARK: - Lights Model

@Observable
class Lights {
    var items: [LightItem] = []
    var selectedLightItemIds = Set<UUID>()
    
    // FIXME: Remove init for proper data feed from a Model
    convenience init(useDemoData: Bool) {
        self.init()
        
        let contentURL = Bundle.main.url(forResource: "Lights", withExtension: "json")
        let contentData = try! Data(contentsOf: contentURL!)
        let decoder = JSONDecoder()
        
        do {
            self.items = try decoder.decode([LightItem].self, from: contentData)
            
            // Sort the items
            self.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        } catch {
            logger.error("\(error, privacy: .public)")
        }
    }
    
    func lightItem(for id: UUID) -> LightItem? {
        return items.first(where: { $0.id == id })
    }
    
    var selectedLightItems: Set<LightItem> {
        // Find the selected LighItems
        // The lists are traversed in this particular way to preseve the selection ordering.
        var lightItems = Set<LightItem>()
        selectedLoop: for (selectedLightItemID) in selectedLightItemIds {
            existingLoop: for (lightItem) in self.items {
                if (lightItem.id == selectedLightItemID) {
                    lightItems.insert(lightItem)
                    continue selectedLoop
                }
            }
        }
        
        return lightItems
    }
}

// MARK: - LightItem Model

@Observable
class LightItem: Identifiable, Codable, Hashable {
    static func == (lhs: LightItem, rhs: LightItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    // FIXME: Account for more bulb and product models
    // 'lighName' is provided for situations where the bulb originally included with a
    // fixture is replaced and its identifiers no longer match a fixture - just a bulb.
    // The light name is used as an additional differentiator.
    private static func getImageName(modelId: String, lightName: String = "") -> String? {
        // Hue Fixture replacements
        if modelId.contains("LCG")
            && lightName.localizedCaseInsensitiveContains("fugato") {
            return "E00-C-57356"    // Hue Fugato Spots
        }
        
        // Hue Fixtures
        if modelId.contains("929002966") { return "E002-57346" }    // Hue Surimu Panel
        if modelId.contains("506313") { return "E00-C-57356" }      // Hue Fugato Spots
        
        // Hue Products and Bulbs
        if modelId.contains("LCG") { return "E027-57383" }  // GU10 bulbs
        if modelId.contains("LCL") { return "E06-A-57450" } // Hue Lightstrip plus
        if modelId.contains("LCT") { return "E015-57365" }  // E14 candle bulbs
        if modelId.contains("LCU") { return "E025-57381" }  // E14 luster bulbs
        if modelId.contains("LCA") { return "E028-57384" }  // A19 bulbs
        if modelId.contains("LOM") { return "E04-D-57421" } // Hue Smart Plug
        
        return nil
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let id: UUID
    
    let lightId: Int
    let name: String
    
    let imageName: String?
    
    enum CodingKeys: CodingKey {
        case light_id, name, image_name
    }
    
    init(id: UUID = UUID(), lightId: Int, name: String, imageName: String? = nil) {
        self.id = id
        self.lightId = lightId
        self.name = name
        self.imageName = imageName
    }
    
    convenience init(light: Light) {
        self.init(lightId: light.lightId,
                  name: light.name,
                  imageName: Self.getImageName(modelId: light.modelId,
                                               lightName: light.name))
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = UUID()
        lightId = try container.decode(Int.self, forKey: .light_id)
        name = try container.decode(String.self, forKey: .name)
        imageName = try container.decodeIfPresent(String.self, forKey: .image_name)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(lightId, forKey: .light_id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(imageName, forKey: .image_name)
    }
}

enum LightItemAction {
    case addToScene(lightItems: [LightItem])
    case removeFromScene(lightItems: [LightItem])
}

// MARK: - Light View

struct LightView: View {
    @Environment(Sidebar.self) private var sidebar
    @Environment(Lights.self) private var lights
    @Environment(WindowItem.self) private var window
    
    @State private var isPresentingSheet: Bool = false
    
    func selectionDidChange(to selectedItems: Set<LightItem>?) {
        guard let selectedItems else {
            logger.info("Selected ''")
            return
        }

        let lights = selectedItems.map { $0.name }
            .joined(separator: ", ")
        logger.info("Selected '\(lights, privacy: .public)'")
    }
    
    private var missingLightItems: [LightItem] {
        get {
            guard let selectedItem = sidebar.selectedSidebarItem else { return [] }
            
            let lights: [Light]
            switch selectedItem.kind {
            case .group:
                lights = window.lights(notInGroupId: selectedItem.groupId)
            case .scene:
                lights = window.lights(inGroupId: selectedItem.groupId, butNotIntSceneId: selectedItem.sceneId!)
            }
            
            let lightItems = lights.map { LightItem(light: $0) }
            return lightItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
    
    var body: some View {
        @Bindable var lights = lights
        
        VStack(alignment: .leading) {
            Text("Lights")
                .font(.title2)
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, -4)
            
            List(lights.items, id: \.self, selection: $lights.selectedLightItemIds) { item in
                HStack {
                    if let imageName = item.imageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 24, maxHeight: 24)
                    } else {
                        Spacer()
                            .frame(width: 32, height: 24)
                    }
                    
                    Text(item.name)
                }
                .id(item.id)
                .listRowSeparator(.hidden)
            }
            .onChange(of: lights.selectedLightItemIds) { previousValue, newValue in
                selectionDidChange(to: lights.selectedLightItems)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LightBottomBarView(isPresentingSheet: $isPresentingSheet)
            }
        }
        .frame(minWidth: 250)
        .sheet(isPresented: $isPresentingSheet) {
        } content: {
            AddLightView(lightItems: missingLightItems)
        }
    }
}

// MARK: - Light Bottom Bar View

struct LightBottomBarView: View {
    @Environment(Sidebar.self) private var sidebar
    @Environment(Lights.self) private var lights
    @Environment(WindowItem.self) private var window
    
    @Binding var isPresentingSheet: Bool
    
    func shouldDisableAddButton() -> Bool {
        // Check if a Group or Scene is selected
        guard let selectedSidebarItem = sidebar.selectedSidebarItem else { return true }
        
        // If a Scene is selected, check if all the lights
        // of its parent Group are already part of the Scene
        if (selectedSidebarItem.kind == .scene) {
            guard window.sceneId != nil else { return true }
            return window.lights(inGroupId: window.groupId!, butNotIntSceneId: window.sceneId!).isEmpty
        }
        
        // If a Group is selected, check if all the lights
        // are already part of the Group
        if (selectedSidebarItem.kind == .group) {
            guard window.groupId != nil else { return true }
            return window.lights(notInGroupId: window.groupId!).isEmpty
        }
        
        return false
    }
    
    func shouldDisableRemoveButton() -> Bool {
        // Check if any Lights are selected
        guard !lights.selectedLightItems.isEmpty else { return true }
        
        return false
    }
    
    var body: some View {
        VStack {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Button(action: {
                    isPresentingSheet = true
                }) {
                    Label("", systemImage: "plus")
                        .padding([.leading, .bottom], 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .help("Add Lights")
                .disabled(shouldDisableAddButton())
                
                Button(action: {
                    window.hasWarning = false
                    Task {
                        switch (sidebar.selectedSidebarItem?.kind) {
                        case .group:
                            try await window.remove(lightIds: Array(lights.selectedLightItems).map({ $0.lightId }), fromGroupId: window.groupId!)
                            
                        case .scene:
                            try await window.remove(lightIds: Array(lights.selectedLightItems).map({ $0.lightId }), fromGroupId: window.groupId!, sceneId: window.sceneId!)
                        default:
                            break
                        }
                        
                        Task { @MainActor in
                            // Remove selection
                            lights.selectedLightItemIds.removeAll()
                        }
                    } catch: { error in
                        window.hasWarning = true
                        
                        // FIXME: Missing error alert
                        logger.error("\(error, privacy: .public)")
                        #warning("Missing Error Alert")
                    }
                }) {
                    Label("", systemImage: "minus")
                        .padding(.bottom, 4)
                        .padding([.leading, .bottom], 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .help("Remove Lights")
                .disabled(shouldDisableRemoveButton())
                
                Spacer()
            }
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Add Light View

struct AddLightView: View {
    @Environment(Sidebar.self) private var sidebar
    @Environment(WindowItem.self) private var window
    
    @Environment(\.dismiss) private var dismiss
    
    var lightItems: [LightItem]
    @State private var addLightItems = Set<LightItem>()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image("Icon")
                    .resizable()
                    .frame(width: 72, height: 72)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Lights to '\(sidebar.selectedSidebarItem?.name ?? "")'")
                        .font(.system(.headline))
                }
                .padding(.top, 6)
            }
            .padding(18)
            
            List(lightItems, id: \.self, selection: $addLightItems) { item in
                HStack {
                    if let imageName = item.imageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 24, maxHeight: 24)
                    } else {
                        Spacer()
                            .frame(width: 32, height: 24)
                    }
                    
                    Text(item.name)
                }
                .id(item.id)
                .listRowSeparator(.hidden)
            }
            // When inside a VStack, a List's size must be set explicitly
            // FIXME: Dynamic Type will probably not work with this
            .frame(idealHeight: lightItems.count <= 12 ? 36 + (CGFloat(lightItems.count) * 30) : 300, maxHeight: 300)
            .scrollBounceBehavior(.basedOnSize)
            .padding([.leading, .trailing], 12)
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .fixedSize()
                .keyboardShortcut(.cancelAction)
                
                Button("\(addLightItems.count) Add Lights") {
                    window.hasWarning = false
                    Task {
                        switch (sidebar.selectedSidebarItem?.kind) {
                        case .group:
                            try await window.add(lightIds: Array(addLightItems).map({ $0.lightId }), toGroupId: window.groupId!)
                            
                        case .scene:
                            try await window.add(lightIds: Array(addLightItems).map({ $0.lightId }), toGroupId: window.groupId!, sceneId: window.sceneId!)
                            
                        default:
                            break
                        }
                        
                        Task { @MainActor in
                            dismiss()
                        }
                    } catch: { error in
                        window.hasWarning = true
                        
                        // FIXME: Missing error alert
                        logger.error("\(error, privacy: .public)")
                        #warning("Missing Error Alert")
                    }
                }
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .disabled(addLightItems.isEmpty)
            }
            .padding(18)
        }
    }
}

// MARK: - Previews

#Preview("LightView") {
    let contentURL = Bundle.main.url(forResource: "Lights", withExtension: "json")
    let contentData = try! Data(contentsOf: contentURL!)
    let sidebar = Sidebar()
    let lights = Lights(json: contentData)
    let window = WindowItem()
    
    return LightView()
        .frame(width: 250, height: 380, alignment: .center)
        .environment(sidebar)
        .environment(lights)
        .environment(window)
}

#Preview("AddLightView") {
    return AddLightView(lightItems: [])
        .frame(width: 250, height: 420, alignment: .center)
}
