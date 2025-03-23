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
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let id: UUID
    
    var lightId: Int
    var name: String
    
    enum CodingKeys: CodingKey {
        case light_id, name
    }
    
    init(id: UUID = UUID(), lightId: Int, name: String) {
        self.id = id
        self.lightId = lightId
        self.name = name
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = UUID()
        lightId = try container.decode(Int.self, forKey: .light_id)
        name = try container.decode(String.self, forKey: .name)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(lightId, forKey: .light_id)
        try container.encode(name, forKey: .name)
    }
}

enum LightItemAction {
    case addToScene(lightItems: [LightItem])
    case removeFromScene(lightItems: [LightItem])
}

// MARK: - Light View

struct LightView: View {
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
    
    var body: some View {
        @Bindable var lights = lights
        
        VStack(alignment: .leading) {
            Text("Lights")
                .font(.title2)
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, -4)
            
            List(lights.items, id: \.self, selection: $lights.selectedLightItemIds) { item in
                Text(item.name)
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
//        isPresentingSheet = false
        } content: {
            AddLightView()
        }
    }
}

struct LightBottomBarView: View {
//    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    @Binding var isPresentingSheet: Bool
    
    var body: some View {
        VStack {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Button(action: {
                    isPresentingSheet = true
//                    let window = NSWindow(
//                        contentRect: .zero,
//                        styleMask: [.titled, .closable],
//                        backing: .buffered,
//                        defer: false
//                    )
//                    
//                    window.titlebarAppearsTransparent = true
//                    
//                    window.center()
//                    window.isReleasedWhenClosed = false
//                    
//                    let view = AddLightView(window: window, deconzModel: deconzModel)
//                        .padding()
//                        .frame( width: 340, height: 400)
//                    
//                    let hosting = NSHostingView(rootView: view)
//                    window.contentView = hosting
//                    hosting.autoresizingMask = [.width, .height]
//                    
//                    NSApp.keyWindow?.beginSheet(window)
                }) {
                    Label("", systemImage: "plus")
                        .padding([.leading, .bottom], 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .help("Add Lights")
                // FIXME: Also disable if all lights in the group are already in the selected scene
//                .disabled(deconzModel.selectedSidebarItem == nil)
                
                Button(action: {
//                    switch (deconzModel.selectedSidebarItem?.type) {
//                    case .group:
//                        Task {
//                            let groupLightItems = deconzModel.lightsList.filter({ !deconzModel.selectedLightItemIDs.contains($0.lightID) })
//                            await deconzModel.modifyGroupLights(groupID: deconzModel.selectedSidebarItem!.groupID!, groupLights: groupLightItems)
//                        }
//                    case .scene:
//                        Task {
//                            let removingLightItems = LightItemAction.removeFromScene(lightItems: Array(deconzModel.selectedLightItems))
//                            await deconzModel.modifySceneLights(groupID: deconzModel.selectedSidebarItem!.groupID!,
//                                                                sceneID: deconzModel.selectedSidebarItem!.sceneID!,
//                                                                sceneLightAction: removingLightItems)
//                            
//                            deconzModel.selectedLightItemIDs.removeAll()
//                        }
//                    default:
//                        break
//                    }
                }) {
                    Label("", systemImage: "minus")
                        .padding(.bottom, 4)
                        .padding([.leading, .bottom], 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .help("Remove Lights")
//                .disabled(deconzModel.selectedSidebarItem == nil ||
//                          deconzModel.selectedLightItemIDs.isEmpty)
                
                Spacer()
            }
            .background(.ultraThinMaterial)
        }
    }
}

struct AddLightView: View {
    @Environment(Sidebar.self) private var sidebar
    @Environment(WindowItem.self) private var window
    
    @Environment(\.dismiss) private var dismiss
//    let window: NSWindow
//    let deconzModel: SceneManagerModel
    
    @State private var lightItems = [LightItem]()
    @State private var addLightItems = Set<LightItem>()
    
    private func loadLightItems() {
        guard let selectedItem = sidebar.selectedSidebarItem else { return }
        
        let lights: [Light]
        switch selectedItem.kind {
        case .group:
            lights = window.lights(notInGroupId: selectedItem.groupId)
        case .scene:
            lights = window.lights(inGroupId: selectedItem.groupId, butNotIntSceneId: selectedItem.sceneId!)
        }
        
        let lightItems = lights.map { LightItem(lightId: $0.lightId, name: $0.name) }
        self.lightItems = lightItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    
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
                Text(item.name)
                    .id(item.id)
                    .listRowSeparator(.hidden)
            }
            // When inside a VStack, a List's size must be set explicitly
            .frame(idealHeight: lightItems.count <= 10 ? CGFloat(lightItems.count) * 28 : 300, maxHeight: 300)
            .padding([.leading, .trailing], 12)
            .task {
                loadLightItems()
            }
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .fixedSize()
                .keyboardShortcut(.cancelAction)
                
                Button("\(addLightItems.count) Add Lights") {
//                    var lightItems = deconzModel.lightsList
                    
//                    Task {
//                        if (deconzModel.selectedSidebarItem!.type == .group) {
//                            lightItems.append(contentsOf: addLightItems)
//                            await deconzModel.modifyGroupLights(groupID: deconzModel.selectedSidebarItem!.groupID!, groupLights: lightItems)
//                        } else if (deconzModel.selectedSidebarItem!.type == .scene) {
//                            let addingLightItems = LightItemAction.addToScene(lightItems: Array(addLightItems))
//                            await deconzModel.modifySceneLights(groupID: deconzModel.selectedSidebarItem!.groupID!,
//                                                                sceneID: deconzModel.selectedSidebarItem!.sceneID!,
//                                                                sceneLightAction: addingLightItems)
//                        }
//                        
                        dismiss()
//                    }
                }
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .disabled(addLightItems.isEmpty)
            }
            .padding(18)
            .background {
                GeometryReader { geometry in
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("LightView") {
    let contentURL = Bundle.main.url(forResource: "Lights", withExtension: "json")
    let contentData = try! Data(contentsOf: contentURL!)
    let lights = Lights(json: contentData)
    let window = WindowItem()
    
    return LightView()
        .frame(width: 250, height: 380, alignment: .center)
        .environment(lights)
        .environment(window)
}

#Preview("AddLightView") {
    return AddLightView()
        .frame(width: 250, height: 420, alignment: .center)
}
