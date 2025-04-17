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

// MARK: - Light View

struct LightView: View {
    @Environment(Sidebar.self) private var sidebar
    @Environment(Lights.self) private var lights
    @Environment(WindowItem.self) private var window
    
    @State private var isPresentingSheet: Bool = false
    @State private var selectedLightItemIds = Set<UUID>()
    
    // LightItems have stable UUIDs, so selection of Lights is preserved across
    // selection changes of Groups/Scenes. It's possible to select multiple
    // lights in one Scene, select a different Scene that has only a subset of
    // the selected lights and click "Apply to Selected" - because selection is
    // preserved, the state would be applied to more lights than those visibly
    // selected. To avoid this, the selected lights are intersected with the
    // lights visible in the Window and the selection stored in 'Lights' is
    // only what is selected and visible.
    func selectionDidChange(to selectedItemIds: Set<UUID>) {
        let lightsSet = Set(lights.items.map(\.self.id))
        lights.selectedLightItemIds = lightsSet.intersection(selectedItemIds)
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
        VStack(alignment: .leading) {
            Text("Lights")
                .font(.title2)
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, -4)
            
            ScrollViewReader { scrollReader in
                List(lights.items, id: \.self, selection: $selectedLightItemIds) { item in
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
                .onChange(of: lights.items) { previousValue, newValue in
                    // Ensure at least one of the selected items is visible when
                    // the list of available lights changes.
                    if let firstItem = selectedLightItemIds.first {
                        Task { @MainActor in
                            scrollReader.scrollTo(firstItem, anchor: .center)
                        }
                        
                        return
                    }
                    
                    if let firstItem = lights.items.first {
                        Task { @MainActor in
                            scrollReader.scrollTo(firstItem, anchor: .center)
                        }
                        
                        return
                    }
                }
                .onChange(of: selectedLightItemIds) { previousValue, newValue in
                    selectionDidChange(to: newValue)
                }
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
                    window.clearWarnings()
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
                        logger.error("\(error, privacy: .public)")
                        
                        window.handleError(error)
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
                    window.clearWarnings()
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
                        logger.error("\(error, privacy: .public)")
                        
                        window.handleError(error)
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
