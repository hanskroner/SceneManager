//
//  Sidebar.swift
//  SceneManager
//
//  Created by Hans Kröner on 20/10/2023.
//

import SwiftUI
import OSLog

import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "sidebar")

// MARK: - Sidebar View

struct SidebarView: View {
    @Environment(Sidebar.self) private var sidebar
    @Environment(WindowItem.self) private var window
    
    func selectionDidChange(to selectedItem: SidebarItem?) {
        // Handle selection of placeholder items
        if selectedItem?.groupId == Sidebar.NEW_GROUP_ID
            || selectedItem?.sceneId == Sidebar.NEW_SCENE_ID {
            window.navigationTitle = nil
            window.navigationSubtitle = nil
            
            window.groupId = nil
            window.sceneId = nil
            
            window.updateLights(forGroupId: nil, sceneId: nil)
            return
        }
        
        // Update window navigation titles to selected names
        let group = sidebar.items.first(where: { $0.groupId == selectedItem?.groupId && $0.sceneId == nil })
        let scene = group?.items.first(where: { $0.sceneId == selectedItem?.sceneId })
        
        window.navigationTitle = group?.name
        window.navigationSubtitle = scene?.name
        
        // Update selection of Group and Scene
        window.groupId = selectedItem?.groupId
        window.sceneId = selectedItem?.sceneId
        
        // Update lights in LightView
        window.updateLights(forGroupId: selectedItem?.groupId, sceneId: selectedItem?.sceneId)
        
        window.clearWarnings()
        Task {
            do {
                // Update the content of the Editors
                if let selectedLightItems = window.lights?.selectedLightItems {
                    let selectedLightIds = selectedLightItems.map({ $0.lightId })
                    try await window.updateEditors(selectedGroupId: selectedItem?.groupId,
                                                   selectedSceneId: selectedItem?.sceneId,
                                                   selectedLightIds: selectedLightIds)
                }
            } catch {
                logger.error("\(error, privacy: .public)")
                
                window.handleError(error)
            }
        }
    }
    
    var body: some View {
        @Bindable var sidebar = sidebar
        
        ScrollViewReader { scrollReader in
            List(selection: $sidebar.selectedSidebarItemId) {
                Section("Groups") {
                    ForEach($sidebar.items, id: \.id) { $item in
                        let children = $item.items
                        if !children.isEmpty {
                            DisclosureGroup(isExpanded: $item.isExpanded) {
                                ForEach(children, id: \.id) { $childItem in
                                    SidebarItemView(item: $childItem)
                                }
                            } label: {
                                SidebarItemView(item: $item)
                            }
                        } else {
                            SidebarItemView(item: $item)
                        }
                    }
                }
            }
            .onKeyPress(.return) {
                // !!!: Get selected sidebar item and set 'isRenaming'
                //        Could be done nicer
                for item in sidebar.items {
                    if item.id == sidebar.selectedSidebarItemId
                        && item.isRenaming == false {
                        item.isRenaming = true
                        return .handled
                    }
                    
                    let children = item.items
                    guard !children.isEmpty else { continue }
                    for child in children {
                        if child.id == sidebar.selectedSidebarItemId
                            && child.isRenaming == false {
                            child.isRenaming = true
                            return .handled
                        }
                    }
                }
                
                return .ignored
            }
            .listStyle(.sidebar)
            .onChange(of: sidebar.items) { previousValue, newValue in
                self.selectionDidChange(to: sidebar.selectedSidebarItem)
            }
            .onChange(of: sidebar.selectedSidebarItemId) { previousItemId, newItemId in
                self.selectionDidChange(to: sidebar.selectedSidebarItem)
            }
            // Use 'scrollToSidebarItemId' to scroll a specific item into view.
            // Note that for the ScrollViewReader proxy to know what item to scroll to, ".id()"
            // must be set in SidebarItemView's view builder.
            .onChange(of: sidebar.scrollToSidebarItemId) {
                if let item = sidebar.scrollToSidebarItemId {
                    sidebar.scrollToSidebarItemId = nil
                    
                    withAnimation {
                        scrollReader.scrollTo(item, anchor: .center)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarBottomBarView()
        }
    }
}

// MARK: - SidebarBottomBar View

struct SidebarBottomBarView: View {
    @Environment(Sidebar.self) private var sidebar
    
    var body: some View {
        VStack {
            Divider()
            HStack {
                Button(action: {
                    // New SidebarItem (Group)
                    withAnimation {
                        _ = sidebar.createSidebarItem()
                    }
                }) {
                    Label("", systemImage: "plus")
                        .padding([.leading, .bottom], 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .help("New Group")
                
                Spacer()
            }
        }
        .glassEffect(in: .rect())
    }
}

// MARK: - SidebarItem View

struct SidebarItemView: View {
    @Environment(Sidebar.self) private var sidebar
    @Environment(WindowItem.self) private var window
    
    @Binding var item: SidebarItem
    
    @State private var isPresentingConfirmation: Bool = false
    @State private var isPresentingDynamicsDelete: Bool = false
    @State private var isFocused: Bool = false
    
    var body: some View {
        // TODO: Click-wait-rename seems impossible with SwiftUI
        //        Force-click rename seems possible through .onLongPressGesture{} modifier
        //        but makes list items behave strangely to selection.
        if (item.isRenaming) {
            EditableText(text: $item.name, hasFocus: $isFocused, isRenaming: $item.isRenaming)
                .id(item.id)
                .onChange(of: isFocused) {
                    // Only act when focus is lost by the TextField the rename is happening in
                    guard isFocused == false else { return }
                    
                    // Clear the 'isRenaming' flag
                    item.isRenaming = false
                    
                    if (item.isNew) {
                        // Clear the 'isNew' flag
                        // It's only useful for the Model to decide between a 'create'
                        // and a 'rename' operation
                        item.isNew = false
                    }
                    else {
                        // Only select the item if it isn't new.
                        // New items are selected at creation and this would interfere with that,
                        // causing the focused TextField and the selected item to be out of sync.
                        sidebar.selectedSidebarItemId = item.id
                    }
                    
                    // Scroll to the renamed item
                    // FIXME: Only scroll if item isn't visible
                    sidebar.scrollToSidebarItemId = item.id
                    
                    // Select between a create or rename operation
                    window.clearWarnings()
                    Task {
                        do {
                            if ((item.groupId == Sidebar.NEW_GROUP_ID) && (item.sceneId == nil)) {
                                do {
                                    let groupId = try await RESTModel.shared.createGroup(name: item.name)
                                    item.groupId = groupId
                                } catch {
                                    // If creation fails, remove the SidebarItem from
                                    // the model and pass the error forward
                                    sidebar.deleteSidebarItem(item)
                                    throw error
                                }
                            } else if ((item.groupId != Sidebar.NEW_GROUP_ID) && (item.sceneId == Sidebar.NEW_SCENE_ID)) {
                                do {
                                    let sceneId = try await RESTModel.shared.createScene(groupId: item.groupId, name: item.name)
                                    item.sceneId = sceneId
                                } catch {
                                    // If creation fails, remove the SidebarItem from
                                    // the model and pass the error forward
                                    sidebar.deleteSidebarItem(item)
                                    throw error
                                }
                            } else if ((item.groupId != Sidebar.NEW_GROUP_ID) && (item.sceneId == nil)) {
                                do {
                                    try await RESTModel.shared.renameGroup(groupId: item.groupId, name: item.name)
                                } catch {
                                    // If rename fails, restore the previous name for
                                    // the Group and pass the error forward
                                    item.restoreName()
                                    throw error
                                }
                            } else {
                                do {
                                    try await RESTModel.shared.renameScene(groupId: item.groupId, sceneId: item.sceneId!, name: item.name)
                                } catch {
                                    // If rename fails, restore the previous name for
                                    // the Group and pass the error forward
                                    item.restoreName()
                                    throw error
                                }
                            }
                            
                            // Update Window properties
                            let group = sidebar.items.first(where: { $0.groupId == item.groupId && $0.sceneId == nil })
                            let scene = group?.items.first(where: { $0.sceneId == item.sceneId })
                            
                            window.navigationTitle = item.kind == .group ? group?.name : nil
                            window.navigationSubtitle = item.kind == .scene ? scene?.name : nil
                            window.groupId = item.groupId
                            window.sceneId = item.sceneId
                            
                            // Keep the lists sorted
                            // Sorting happens as part of the Task, otherwise the reference to 'item' will change
                            if (item.kind == .group) {
                                sidebar.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                            } else {
                                let parent = sidebar.items.filter({ $0.items.contains(item) }).first!
                                parent.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                            }
                            
                            // Signal RESTModel to issue a notification that
                            // it's data has been updated.
                            RESTModel.shared.signalUpdate()
                        } catch {
                            logger.error("\(error, privacy: .public)")
                            
                            window.handleError(error)
                        }
                    }
                }
                .onAppear {
                    isFocused = true
                }
                .background(.thinMaterial)
        } else {
            HStack(spacing: 4) {
                Text(item.name)
                    .frame(maxHeight: .infinity)
                
                if item.hasDynamics {
                    Image("scene-dynamics")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 20)
                }
            }
            .id(item.id)
            .contextMenu {
                if (item.kind == .group) {
                    Button(action: {
                        // New SidebarItem (Scene)
                        withAnimation {
                            _ = sidebar.createSidebarItem(parent: item)
                        }
                    }, label: {
                        Text("New Scene")
                    })
                }
                
                Button(action: {
                    item.isRenaming = true
                }, label: {
                    Text("Rename " + (item.kind == .group ? "Group" : "Scene"))
                })
                
                Button(action: {
                    isPresentingConfirmation = true
                }, label: {
                    Text("Delete " + (item.kind == .group ? "Group" : "Scene"))
                })
                
                // TODO: Remove 'dynamics' from scenes that have them
                if (item.hasDynamics) {
                    Divider()
                    
                    Button(action: {
                        isPresentingDynamicsDelete = true
                    }, label: {
                        Text("Delete Dynamic Scene")
                    })
                }
            }
            .confirmationDialog("Are you sure you want to delete '\(item.name)'?", isPresented: $isPresentingConfirmation) {
                Button("Delete " + (item.kind == .group ? "Group" : "Scene"), role: .destructive) {
                    // Call on the REST API to perform deletion
                    window.clearWarnings()
                    Task {
                        do {
                            if (item.kind == .group) {
                                try await RESTModel.shared.deleteGroup(groupId: item.groupId)
                            } else {
                                try await RESTModel.shared.deleteScene(groupId: item.groupId, sceneId: item.sceneId!)
                            }
                            
                            // Deleting happens as part of the Task, otherwise the reference to 'item' will change
                            sidebar.deleteSidebarItem(item)
                            
                            // Update Window properties
                            window.navigationTitle = nil
                            window.navigationSubtitle = nil
                            window.groupId = nil
                            window.sceneId = nil
                            
                            // Signal RESTModel to issue a notification that
                            // it's data has been updated.
                            RESTModel.shared.signalUpdate()
                        } catch {
                            logger.error("\(error, privacy: .public)")
                            
                            window.handleError(error)
                        }
                    }
                }
            }
            .confirmationDialog("Are you sure you want to delete the Dynamic Scene in '\(item.name)'?", isPresented: $isPresentingDynamicsDelete) {
                Button("Delete Dynamic Scene", role: .destructive) {
                    // Call on the REST API to perform deletion
                    window.clearWarnings()
                    Task {
                        do {
                            // The call on 'window' will take care of updating the UI models, including
                            // resetting this 'item's 'hasDynamics' flags and updating the Scene's definition
                            try await window.deleteDynamicScene(fromGroupId: item.groupId, sceneId: item.sceneId!)
                        } catch {
                            logger.error("\(error, privacy: .public)")
                            
                            window.handleError(error)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Sidebar") {
    let contentURL = Bundle.main.url(forResource: "Sidebar", withExtension: "json")
    let contentData = try! Data(contentsOf: contentURL!)
    let sidebar = Sidebar(json: contentData)
    let window = WindowItem()
    
    return SidebarView()
        .frame(width: 200, height: 420, alignment: .center)
        .environment(sidebar)
        .environment(window)
}
