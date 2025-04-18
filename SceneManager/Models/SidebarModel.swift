//
//  SidebarModel.swift
//  SceneManager
//
//  Created by Hans Kröner on 17/04/2025.
//

import SwiftUI
import Combine
import OSLog

import deCONZ

// MARK: - Sidebar Model

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "sidebar")
private let uuidNamespace = "com.hanskroner.scenemanager.sidebar"

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
    
    func sidebarItem(forGroupId groupId: Int?, sceneId: Int? = nil) -> SidebarItem? {
        for item in items {
            if item.groupId == groupId && item.sceneId == sceneId { return item }
            if let child = item.items.first(where: { $0.groupId == groupId && $0.sceneId == sceneId }) { return child }
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
    static func == (lhs: SidebarItem, rhs: SidebarItem) -> Bool {
        return lhs.id == rhs.id
            && lhs._fetched == rhs._fetched
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    enum Kind: String, Codable {
        case group
        case scene
    }
    
    let id: UUID
    
    var name: String
    var items: [SidebarItem]
    
    var groupId: Int
    var sceneId: Int?
    
    private var _isRenaming: Bool = false
    private var _shadowName: String = ""
    
    // Set when the SidebarItem is created.
    // It's used in the Equatable extension to nudge SwiftUI into thiking two
    // SidebarItems with identical UUIDs are actually different and to decide
    // to redraw Views that depend on this SidebarItem.
    private let _fetched: Date
    
    // State
    /// Is this 'SidebarItem' a recently-created one that hasn't been persisted by the model?
    var isNew: Bool = false
    /// Is this 'SidebarItem' being rendered with its 'children' rendered as expanded?
    var isExpanded: Bool = false
    /// Does this 'SidebarItem' represent an entity with dynamic actions?
    var hasDynamics: Bool = false
    
    // Store the PresetItem's name in a shadow variable when a rename operation
    // starts. Should the operation fail, the previous name can be restored by
    // calling 'restoreName'.
    /// Is this 'SidebarItem' being rendered as a 'TextField' allowing its 'text' property to be updated?
    var isRenaming: Bool {
        get {
            return _isRenaming
        }
        
        set {
            _isRenaming = newValue
            _shadowName = newValue ? name : _shadowName
        }
    }
    
    func restoreName() {
        name = _shadowName
    }
    
    init(name: String, items: [SidebarItem] = [], groupId: Int, sceneId: Int? = nil, hasDynamics: Bool = false) {
        self.id = UUID(namespace: uuidNamespace, input: "\(groupId)" + (sceneId != nil ? "-\(sceneId!)" : ""))!
        
        self.name = name
        self.items = items
        
        self.groupId = groupId
        self.sceneId = sceneId
        
        self.hasDynamics = hasDynamics
        
        self._fetched = Date()
    }
    
    enum CodingKeys: CodingKey {
        case kind, name, items, group_id, scene_id
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        let groupId = try container.decode(Int.self, forKey: .group_id)
        self.groupId = groupId
        let sceneId = try container.decodeIfPresent(Int.self, forKey: .scene_id)
        self.sceneId = sceneId
        items = try container.decodeIfPresent([SidebarItem].self, forKey: .items, configuration: GroupDecodingConfiguration(groupId: groupId)) ?? []
        
        id = UUID(namespace: uuidNamespace, input: "\(groupId)" + (sceneId != nil ? "-\(sceneId!)" : ""))!
        self._fetched = Date()
    }
    
    required init(from decoder: Decoder, configuration: GroupDecodingConfiguration) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        let groupId = configuration.groupId
        self.groupId = groupId
        let sceneId = try container.decodeIfPresent(Int.self, forKey: .scene_id)
        self.sceneId = sceneId
        items = try container.decodeIfPresent([SidebarItem].self, forKey: .items) ?? []
        
        id = UUID(namespace: uuidNamespace, input: "\(groupId)" + (sceneId != nil ? "-\(sceneId!)" : ""))!
        self._fetched = Date()
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
