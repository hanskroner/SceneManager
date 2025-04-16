//
//  Sidebar.swift
//  SceneManager
//
//  Created by Hans Kröner on 20/10/2023.
//

import SwiftUI
import Combine
import OSLog

import deCONZ

// MARK: - Sidebar Model

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "sidebar")

@Observable
class Sidebar {
    static let NEW_GROUP_ID = -999
    static let NEW_SCENE_ID = -999
    
    var items: [SidebarItem] = []
    
    var selectedSidebarItemId: UUID? = nil
    var scrollToSidebarItemId: UUID? = nil
    
    // FIXME: Remove init for proper data feed from a Model
    convenience init(useDemoData: Bool) {
        self.init()
        
        let contentURL = Bundle.main.url(forResource: "Sidebar", withExtension: "json")
        let contentData = try! Data(contentsOf: contentURL!)
        let decoder = JSONDecoder()
        
        do {
            self.items = try decoder.decode([SidebarItem].self, from: contentData)
            
            // Sort the items and the items' items.
            self.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            for (item) in self.items.filter({ !($0.items.isEmpty) }) {
                item.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
        } catch {
            logger.error("\(error, privacy: .public)")
        }
    }
    
    func sidebarItem(for id: UUID) -> SidebarItem? {
        for item in items {
            if item.id == id { return item }
            if let child = item.items.first(where: { $0.id == id }) { return child }
        }
        
        return nil
    }
    
    var selectedSidebarItem: SidebarItem? {
        guard let selectedId = self.selectedSidebarItemId else { return nil }
        return sidebarItem(for: selectedId)
    }
    
    func createSidebarItem(parent: SidebarItem? = nil) -> SidebarItem {
        let kind: SidebarItem.Kind = parent == nil ? .group : .scene
        
        // In keeping with modern macOS design, SidebarItem are created immediately using a
        // proposed name instead of presenting a Window to the user and asking for a name.
        // The code below only injects an item into the Sidebar - no calls to the REST API are
        // made. The injected SidebarItem is immediately made ready to rename. Once the rename
        // is performed, the View will call on the Model to create either a Group or a Scene via
        // the REST API.
        
        // Go through the existing names and propose an unused placeholder name for the new
        // SidebarItem. The REST API produces an error when attempting to create a new Group or
        // Scene with an already-existing name - this is just to make the creation process
        // friendlier.
        let proposedText = "New \(kind == .group ? "Group" : "Scene")"
        let existingTexts: [String]
        var proposedTextSuffix = ""
        
        if (kind == .group) {
            existingTexts = self.items.compactMap({ $0.name })
        } else {
            existingTexts = parent!.items.compactMap({ $0.name })
        }
        
        for index in 1 ..< 100 {
            if !existingTexts.contains(proposedText + proposedTextSuffix) { break }
            proposedTextSuffix = " " + String(index)
        }
        
        // Create a new SidebarItem with the placeholder text and a pair of group/scene IDs.
        // The constant values will be used as sentinels by the rename function, which is
        // where calls to the REST API will be issued from.
        let newSidebarItem = SidebarItem(name: proposedText + proposedTextSuffix,
                                         groupId: kind == .group ? Sidebar.NEW_GROUP_ID : parent!.groupId,
                                         sceneId: kind == .scene ? Sidebar.NEW_SCENE_ID : nil)
        newSidebarItem.isNew = true
        newSidebarItem.isRenaming = true
        
        if (kind == .group) {
            self.items.append(newSidebarItem)
        } else {
            // Make sure parents are expanded so the new child is visible
            parent!.isExpanded = true
            parent!.items.append(newSidebarItem)
        }
        
        // Don't sort 'items' yet, so the new item is always at the bottom.
        // Request the new SidebarItem to be selected and scrolled into view.
        self.selectedSidebarItemId = newSidebarItem.id
        self.scrollToSidebarItemId = newSidebarItem.id
        
        return newSidebarItem
    }
    
    func deleteSidebarItem(_ deleteItem: SidebarItem) {
        // Try to find the SidebarItem in the "items" list
        if self.items.contains(deleteItem) {
            self.items.removeAll { $0 == deleteItem }
            return
        }
        
        // Try to find the SidebarItem in the items' "children" list
        for parentItem in self.items {
            if (parentItem.items.contains(deleteItem)) {
                parentItem.items.removeAll { $0 == deleteItem }
                return
            }
        }
    }
}

// MARK: - SidebarItem Model

struct GroupDecodingConfiguration {
    init(groupId: Int) {
        self.groupId = groupId
    }
    
    let groupId: Int
}

@Observable
class SidebarItem: Identifiable, Codable, DecodableWithConfiguration, Hashable {
    enum Kind: String, Codable {
        case group
        case scene
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let id: UUID
    
    var name: String
    var items: [SidebarItem]
    
    var groupId: Int
    var sceneId: Int?
    
    // State
    /// Is this 'SidebarItem' a recently-created one that hasn't been persisted by the model?
    var isNew: Bool = false
    /// Is this 'SidebarItem' being rendered as a 'TextField' allowing its 'text' property to be updated?
    var isRenaming: Bool = false
    /// Is this 'SidebarItem' being rendered with its 'children' rendered as expanded?
    var isExpanded: Bool = false
    
    init(id: UUID = UUID(), name: String, items: [SidebarItem] = [], groupId: Int, sceneId: Int? = nil) {
        self.id = id
        
        self.name = name
        self.items = items
        
        self.groupId = groupId
        self.sceneId = sceneId
    }
    
    enum CodingKeys: CodingKey {
        case kind, name, items, group_id, scene_id
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = UUID()
        name = try container.decode(String.self, forKey: .name)
        let groupId = try container.decode(Int.self, forKey: .group_id)
        self.groupId = groupId
        sceneId = try container.decodeIfPresent(Int.self, forKey: .scene_id)
        items = try container.decodeIfPresent([SidebarItem].self, forKey: .items, configuration: GroupDecodingConfiguration(groupId: groupId)) ?? []
    }
    
    required init(from decoder: Decoder, configuration: GroupDecodingConfiguration) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = UUID()
        name = try container.decode(String.self, forKey: .name)
        groupId = configuration.groupId
        sceneId = try container.decodeIfPresent(Int.self, forKey: .scene_id)
        items = try container.decodeIfPresent([SidebarItem].self, forKey: .items) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(name, forKey: .name)
        try container.encode(items, forKey: .items)
        try container.encode(groupId, forKey: .group_id)
        try container.encode(sceneId, forKey: .scene_id)
    }
    
    var kind: SidebarItem.Kind {
        if (sceneId == nil) {
            return .group
        } else {
            return .scene
        }
    }
}

extension SidebarItem: Equatable {
    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @Environment(Sidebar.self) private var sidebar
    @Environment(WindowItem.self) private var window
    
    @FocusState private var isFocused: Bool
    
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
        // !!!: Selection is lost
        //      'updateLights' creates new LightItems, which do not use a stable UUID.
        //      This causes the list selection to be "lost" when navigating to a new
        //      Group or Scene - even if they also contain the Light that was selected.
        //      If this behaviour causes confusion, a stable UUID (like the one used by
        //      the deCONZ Models) could be used instead. This would preserve the selection
        //      but would require a trigger to refresh the state (and potentially other
        //      attributes) of the selection, since these only change when the light selecion
        //      changes
        window.updateLights(forGroupId: selectedItem?.groupId, sceneId: selectedItem?.sceneId)
        
        window.hasWarning = false
        Task {
            // Update the Dynamics Editor when sidebar selection changes
            window.dynamicsEditorText = try await window.jsonDynamicState(forGroupId: selectedItem?.groupId,
                                                                      sceneId: selectedItem?.sceneId)
            
            // Switch to the Dynamics Editor if it wasn't already selected
            if ((window.dynamicsEditorText != "") && (window.selectedEditorTab != .dynamicScene)) {
                Task { @MainActor in
                    window.selectedEditorTab = .dynamicScene
                }
            }
        } catch: { error in
            window.hasWarning = true
            
            // FIXME: Missing error alert
            logger.error("\(error, privacy: .public)")
            #warning("Missing Error Alert")
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
                // 'safeAreaInsets' doesn't seem to allow the List's contents to "be seen"
                // through the bottom bar's ultra-thin material. Instead, this spacer acts
                // as the inset and the bottom bar is drawn in an overlay.
                Spacer()
                    .frame(height: 1)
            }
            .onKeyPress(.return) {
                // FIXME: Get selected sidebar item and set 'isRenaming'
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
        .overlay(alignment: .bottom) {
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
        .background(.thinMaterial)
    }
}

// MARK: - EditableText View

struct EditableText: View {
    @Binding var text: String
    @Binding var hasFocus: Bool
    @Binding var isRenaming: Bool
    
    @State private var editingText: String
    @FocusState private var isFocused: Bool
    
    init(text: Binding<String>, hasFocus: Binding<Bool>, isRenaming: Binding<Bool>) {
        self._text = text
        self._hasFocus = hasFocus
        self._isRenaming = isRenaming
        self.editingText = text.wrappedValue
    }
    
    var body: some View {
        TextField("", text: $editingText)
            .focused($isFocused, equals: true)
            .onSubmit(of: .text) {
                text = editingText
            }
            .onExitCommand {
                editingText = text
                isRenaming = false
            }
            .onChange(of: isFocused) { previousValue, newValue in
                // Send the focus back to the parent
                hasFocus = newValue
            }
            .onChange(of: hasFocus) { previousValue, newValue in
                // Update the focus if it is set externally
                if (newValue == true && isFocused == false) {
                    isFocused = true
                }
                
                if (newValue == false && isFocused == true) {
                    isFocused = false
                }
            }
    }
}

// MARK: - SidebarItem View

struct SidebarItemView: View {
    @Environment(Sidebar.self) private var sidebar
    @Environment(WindowItem.self) private var window
    
    @Binding var item: SidebarItem
    
    @State private var isPresentingConfirmation: Bool = false
    @State private var isFocused: Bool = false
    
    // FIXME: Causes focus issues
    //        Just declaring this variable inside the View - regardless of whether it is used
    //        for anything - causes focus issues. Having it present makes the Sidebar require
    //        two clicks to select an item when focus is outside of the Sidebar.
    //        Moving @FocusState to EditableText has fixed the issue.
    // @FocusState private var isFocused: Bool
    
    var body: some View {
        // FIXME: Click-wait-rename seems impossible with SwiftUI
        //        Force-click rename seems possible through .onLongPressGesture{} modifier
        //        but makes list items behave strangely to selection.
        if (item.isRenaming) {
            EditableText(text: $item.name, hasFocus: $isFocused, isRenaming: $item.isRenaming)
                .id(item.id)
                .onChange(of: isFocused) {
                    // Only act when focus is lost by the TextField the rename is happening in
                    guard isFocused == false else { return }
                    logger.info("Losing focus on '\(item.name, privacy: .public)'")
                    
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
                    window.hasWarning = false
                    Task {
                        if ((item.groupId == Sidebar.NEW_GROUP_ID) && (item.sceneId == nil)) {
                            let groupId = try await RESTModel.shared.createGroup(name: item.name)
                            
                            guard let groupId else {
                                sidebar.deleteSidebarItem(item)
                                return
                            }
                            
                            item.groupId = groupId
                        } else if ((item.groupId != Sidebar.NEW_GROUP_ID) && (item.sceneId == Sidebar.NEW_SCENE_ID)) {
                            let sceneId = try await RESTModel.shared.createScene(groupId: item.groupId, name: item.name)
                            
                            guard let sceneId else {
                                sidebar.deleteSidebarItem(item)
                                return
                            }
                            
                            item.sceneId = sceneId
                        } else if ((item.groupId != Sidebar.NEW_GROUP_ID) && (item.sceneId == nil)) {
                            try await RESTModel.shared.renameGroup(groupId: item.groupId, name: item.name)
                        } else {
                            try await RESTModel.shared.renameScene(groupId: item.groupId, sceneId: item.sceneId!, name: item.name)
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
                    } catch: { error in
                        window.hasWarning = true
                        
                        // FIXME: Missing error alert
                        logger.error("\(error, privacy: .public)")
                        #warning("Missing Error Alert")
                    }
                }
                .onAppear {
                    logger.info("Focusing '\(item.name, privacy: .public)'")
                    isFocused = true
                }
                .background(.thinMaterial)
        } else {
            Text(item.name)
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
                }
                .confirmationDialog("Are you sure you want to delete '\(item.name)'?", isPresented: $isPresentingConfirmation) {
                    Button("Delete " + (item.kind == .group ? "Group" : "Scene"), role: .destructive) {
                        // Call on the REST API to perform deletion
                        window.hasWarning = false
                        Task {
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
                        } catch: { error in
                            window.hasWarning = true
                            
                            // FIXME: Missing error alert
                            logger.error("\(error, privacy: .public)")
                            #warning("Missing Error Alert")
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
