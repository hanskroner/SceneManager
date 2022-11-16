//
//  SceneManagerModel.swift
//  SceneManager
//
//  Created by Hans Kröner on 06/11/2022.
//

import SwiftUI

enum ModifySceneRange {
    case allLightsInScene
    case selectedLightsOnly
}

class SceneManagerModel: ObservableObject {
    private let deconzClient = deCONZRESTClient()
    
    private let decoder = JSONDecoder()
    
    var selectedSidebarItem: SidebarItem? {
        didSet {
            if (oldValue?.groupID != selectedSidebarItem?.groupID) {
                self.selectedLightItemIDs.removeAll()
            }
            
            if (selectedSidebarItemID == nil) {
                self.lightsList = [LightItem]()
            }
            
            Task {
                await self.refreshLightsList(forGroupID: selectedSidebarItem?.groupID, sceneID: selectedSidebarItem?.sceneID)
                
                // Refresh the Light List selecction and potentially the Light State of the selected Light
                self.selectedLightItems = lightItemsFor(ids: selectedLightItemIDs)
                await MainActor.run {
                    self.jsonStateText = self.selectedLightItems.first?.state ?? ""
                }
            }
        }
    }
    
    @Published var selectedSidebarItemID: String? = nil {
        didSet {
            self.selectedSidebarItem = sidebarItemFor(id: selectedSidebarItemID)
        }
    }
    
    var selectedLightItems = Set<LightItem>()
    
    @Published var selectedLightItemIDs = Set<Int>() {
        didSet {
            self.selectedLightItems = lightItemsFor(ids: selectedLightItemIDs)
        }
    }
    
    @Published var jsonStateText = ""
    
    @Published var scrollToItem: String? {
        didSet {
            prepareListSnapshot()
        }
    }
    
    @Published var sidebarItems = [SidebarItem]()
    @Published var lightsList = [LightItem]()

    private var cacheLights: [Int: deCONZLight]?
    private var cacheGroups: [Int: deCONZGroup]?
    private var cacheScenes: [Int: [Int: deCONZScene]]?

    private var copyForSnapshot: [SidebarItem]?

    init() {
        Task {
            self.cacheLights = try await deconzClient.getAllLights()
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
            
            await refreshSidebarItems()
        }
    }
    
    private func sidebarItemFor(id: String?) -> SidebarItem? {
        // Find the selected SidebarItem by the provided ID
        var sidebarItem: SidebarItem?
        groupLoop: for (group) in self.sidebarItems {
            if (group.id == id) {
                sidebarItem = group
                break groupLoop
            }
        
            sceneLoop: for (scene) in group.children ?? [] {
                if (scene.id == id) {
                    sidebarItem = scene
                    break groupLoop
                }
            }
        }
        
        let returnValue = sidebarItem
        return returnValue
    }
    
    private func lightItemsFor(ids: Set<Int>) -> Set<LightItem> {
        // Find the selected LighItems by the provided IDs
        // The lists are traversed in this particular way to preseve the selection ordering.
        var lightItems = Set<LightItem>()
        selectedLoop: for (selectedLightItemID) in ids {
            existingLoop: for (lightItem) in self.lightsList {
                if (lightItem.lightID == selectedLightItemID) {
                    lightItems.insert(lightItem)
                    break selectedLoop
                }
            }
        }
                
//        for (lightItem) in self.lightsList {
//            if ids.contains(lightItem.lightID) {
//                lightItems.insert(lightItem)
//            }
//        }
        
        return lightItems
    }
    
    // MARK: - SibedarItems Snapshot Methods

    private func prepareListSnapshot() {
        // Store a copy of the existing items
        self.copyForSnapshot = self.sidebarItems
        
        // Get a list of only the 'parent' nodes. Nodes with children will have their 'children' nodes
        // set to an empty array, while nodes with no children will have 'nil'
        var sidebarItems = self.sidebarItems.map({ item in
            var item = item
            
            if item.children != nil {
                item.children = [SidebarItem]()
            }
            
            return item
        })
        
        // Attach children back to the parents that are expanded
        for (index, item) in self.sidebarItems.enumerated() {
            if !item.isExpanded { continue }
            
            sidebarItems[index].children = self.copyForSnapshot![index].children
        }
        
        // Set the 'snapshot' list as the item list.
        self.sidebarItems = sidebarItems
    }
    
    func removeListSnapshot() {
        guard let copyForSnapshot = self.copyForSnapshot else { return }
        self.scrollToItem = nil
        self.sidebarItems = copyForSnapshot
        self.copyForSnapshot = nil
    }
    
    // MARK: - Publisher-related Methods
    
    private func refreshSidebarItems() async {
        var updatedSidebarItems = [SidebarItem]()
        
        guard let cacheGroups = self.cacheGroups,
              let cacheScenes = self.cacheScenes else { return }
        
        // Prepare a Dictionary that holds the current expansion state of Groups
        let storedExpansions = self.sidebarItems.reduce(into: [Int: Bool]()) { $0[$1.groupID] = $1.isExpanded }
        
        for (_, group) in cacheGroups {
            var groupItem = SidebarItem(id: "G\(group.id)", name: group.name, groupID: group.id, isExpanded: storedExpansions[group.id] ?? false)
            
            for (_, scene) in cacheScenes[group.id] ?? [:] {
                let sceneItem = SidebarItem(id: "G\(group.id)S\(scene.id)", name: scene.name, parentName: group.name, groupID: group.id, sceneID: scene.id)
                
                if (groupItem.children == nil) {
                    groupItem.children = [SidebarItem]()
                }
                
                groupItem.children!.append(sceneItem)
            }
            
            // Sort Scene names alphabetically
            groupItem.children = groupItem.children?.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            updatedSidebarItems.append(groupItem)
        }
        
        // Sort Group names alphabetically
        let list = updatedSidebarItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        await MainActor.run {
            self.sidebarItems = list
        }
    }
    
    private func refreshLightsList(forGroupID groupID: Int?, sceneID: Int?) async {
        guard let cacheLights = self.cacheLights,
              let cacheGroups = self.cacheGroups,
              let groupID = groupID
        else { return }
        
        var updatedSceneLights = [LightItem]()
        
        if let sceneID = sceneID {
            // If a Scene ID is provided, build a list of Lights belonging to that Group's Scene
            
            guard let sceneAttributes = try? await deconzClient.getSceneAttributes(groupID: groupID, sceneID: sceneID) else {
                // FIXME: Update 'self.sceneLights'
                return
            }
            
            for (lightID, lightState) in sceneAttributes {
                guard let light = cacheLights[lightID]
                else {
                    // FIXME: Update 'self.sceneLights'
                    return
                }
                
                let stateString = lightState.prettyPrint
                updatedSceneLights.append(LightItem(id: "G\(groupID)S\(sceneID)L\(lightID)", lightID: lightID, name: light.name, state: stateString))
            }
        } else {
            // If no Scene ID is provided, build a list of Lights belonging to that Group ID
            
            for (lightID) in cacheGroups[groupID]?.lights ?? [] {
                guard let light = cacheLights[lightID]
                else {
                    // FIXME: Update 'self.sceneLights'
                    return
                }
                
                updatedSceneLights.append(LightItem(id: "G\(groupID)L\(lightID)", lightID: lightID, name: light.name, state: ""))
            }
        }
        
        // Sort Light names alphabetically
        let list = updatedSceneLights.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        await MainActor.run {
            self.lightsList = list
        }
    }
    
    func lightsIn(groupID: Int, butNotIn sceneID: Int) async -> [LightItem] {
        var missingLightItems = [LightItem]()
        
        guard let cacheLights = self.cacheLights,
              let cacheGroups = self.cacheGroups,
              let groupLights = cacheGroups[groupID]?.lights,
              let sceneAttributes = try? await deconzClient.getSceneAttributes(groupID: groupID, sceneID: sceneID)
        else { return [LightItem]() }
        
        let groupLightsIDs = groupLights.compactMap({ Int($0) })
        let sceneLightsIDs = sceneAttributes.compactMap({ Int($0.key) })
        
        let lightsInGroup = cacheLights.filter({ groupLightsIDs.contains($0.0) })
        let lightsInGroupButNotInScene = lightsInGroup.filter({ !sceneLightsIDs.contains($0.0) })
        
        for (lightID, lightInGroupButNotInScene) in lightsInGroupButNotInScene {
            missingLightItems.append(LightItem(id: "ADD\(groupID)L\(lightID)", lightID: lightID, name: lightInGroupButNotInScene.name, state: ""))
        }
        
        return missingLightItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    
    func lightsNotIn(groupID: Int) -> [LightItem] {
        var missingLightItems = [LightItem]()
        
        guard let cacheLights = self.cacheLights,
              let cacheGroups = self.cacheGroups,
              let groupLights = cacheGroups[groupID]?.lights
        else { return [LightItem]() }
        
        let groupLightsIDs = groupLights.compactMap({ Int($0) })
        
        let lightsNotInGroup = cacheLights.filter({ !groupLightsIDs.contains($0.0) })
        
        for (lightID, lightNotInGroup) in lightsNotInGroup {
            missingLightItems.append(LightItem(id: "ADD\(groupID)L\(lightID)", lightID: lightID, name: lightNotInGroup.name, state: ""))
        }
        
        return missingLightItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    
    func createNewSidebarItem(groupID: Int?, sceneID: Int?) async {
        // In keeping with modern macOS design, SidebarItem are created immediately using a proposed name
        // instead of presenting a Window to the user and asking for a name. The code below only injects an
        // item into the Sidebar - no calls to the REST API are made. The injected SidebarItem is immediately
        // made ready to rename. Once the rename is performed, the View will call on the Model to create
        // either a Group or a Scene via the REST API.
        
        // First, go through the existing names and propose an un-used placeholder name for the new
        // Sidebar Item. The REST API will produce an error when attempting to create a new Group or Scene
        // with an already-existing name - this is just to make the creation process friendlier.
        let newName: String
        let proposedName = "New \(groupID == nil ? "Group" : "Scene")"
        let existingNames: [String]
        var proposedNameSuffix = ""
        
        if ((groupID == nil) && (sceneID == nil)) {
            // A new 'Group' Sidebar Item is being created
            existingNames = sidebarItems.compactMap({ $0.name })
        } else {
            // A new 'Scene' Sidebar Item is being created
            existingNames = sidebarItems.first(where: { $0.groupID == groupID })?.children?.compactMap({ $0.name }) ?? [String]()
        }
        
        for index in 1 ..< 100 {
            if !existingNames.contains(proposedName + proposedNameSuffix) { break }
            proposedNameSuffix = String(index)
        }
        
        newName = proposedName + proposedNameSuffix
        
        // The SidebarItem for the new group is created with '-999' as its GroupID. It is also flagged as
        // 'renaming' and 'wantingFocus' to have the View draw it as a TextField with focus - allowing the
        // user to immediately provide the actual name for the new group. The View identifies items with
        // GroupID '-999' as "new" and routes the submission after renaming to "createGroup" instead of the
        // usual "renameGroup". The flags are temporary, as this SidebarItem will be released when the Model's
        // List Model is refreshed after performing the actual group creation via the REST API.
        
        let newGroupID = groupID ?? -999
        let newSceneID = sceneID ?? -999
        let newSidebarItem = SidebarItem(id: newName, name: newName, groupID: newGroupID, sceneID: newSceneID, isRenaming: true, wantsFocus: true)
        await MainActor.run {
            // The SidebarItem is added to the Model's List Model. The List Model is then sorted before being
            // presented again to the user. Finally, the newly created SidebarItem is scrolled into view.
            var mutableCopy = self.sidebarItems
            if ((groupID == nil) && (sceneID == nil)) {
                // A new 'Group' Sidebar Item is being created
                mutableCopy.append(newSidebarItem)
                self.sidebarItems = mutableCopy.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            } else {
                // A new 'Scene' Sidebar Item is being created
                guard let groupIndex = sidebarItems.firstIndex(where: { $0.groupID == groupID }) else { return }
                
                // If this is creating a new 'Scene' Sidebar Item, expand its parent 'Group' if it was collapsed
                self.sidebarItems[groupIndex].isExpanded = true
                
                if (self.sidebarItems[groupIndex].children == nil) {
                    self.sidebarItems[groupIndex].children = [SidebarItem]()
                }
                
                self.sidebarItems[groupIndex].children?.append(newSidebarItem)
            }
            
            // Scroll to the new Sidebar Item to make it visible for the user
            self.scrollToItem = newName
        }
    }
    
    // MARK: - deCONZ Group CRUD Methods
    
    func createGroup(name: String) async {
        do {
            let _ = try await deconzClient.createGroup(name: name)
            
            // Fetch the Group and Scene information from the REST API and update the model's cache. This
            // will trigger SwiftUI to redraw the UI, which will now include the newly-created group and not
            // the placeholder SidebarItem that wa used to name it.
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
        } catch {
            // FIXME: Handle errors
            print(error)
        }
        
        Task {
            await refreshSidebarItems()
        }
    }
    
    func renameGroup(groupID: Int, name: String) async {
        do {
            try await deconzClient.setGroupAttributes(groupID: groupID, name: name)
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
        } catch {
            // FIXME: Handle errors
            print(error)
        }
        
        Task {
            await refreshSidebarItems()
        }
    }
    
    func modifyGroupLights(groupID: Int, groupLights: [LightItem]) async {
        let groupLightsIDs = groupLights.map({ $0.lightID }).sorted()
        
        do {
            try await deconzClient.setGroupAttributes(groupID: groupID, lights: groupLightsIDs)
            
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
        } catch {
            // FIXME: Handle errors
            print(error)
        }
        
        Task {
            await refreshLightsList(forGroupID: groupID, sceneID: nil)
        }
    }
    
    func deleteGroup(groupID: Int) async {
        do {
            try await deconzClient.deleteGroup(groupID: groupID)
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
        } catch {
            // FIXME: Handle errors
            print(error)
        }
        
        Task {
            await refreshSidebarItems()
        }
    }
    
    // MARK: - deCONZ Scene CRUD Methods
    
    func createScene(groupID: Int, name: String) async {
        do {
            let _ = try await deconzClient.createScene(groupID: groupID, name: name)
            
            // Fetch the Group and Scene information from the REST API and update the model's cache. This
            // will trigger SwiftUI to redraw the UI, which will now include the newly-created group and not
            // the placeholder SidebarItem that wa used to name it.
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
        } catch {
            // FIXME: Handle errors
            print(error)
        }
        
        Task {
            await refreshSidebarItems()
        }
    }
    
    func renameScene(groupID: Int, sceneID: Int, name: String) async {
        do {
            try await deconzClient.setSceneAttributes(groupID: groupID, sceneID: sceneID, name: name)
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
        } catch {
            // FIXME: Handle errors
            print(error)
        }
        
        Task {
            await refreshSidebarItems()
        }
    }
    
    func modifySceneLights(groupID: Int, sceneID: Int, sceneLights: [LightItem]) async {
        let lightsNotInGroup = lightsNotIn(groupID: groupID)
        let lightsNotInScene = await lightsIn(groupID: groupID, butNotIn: sceneID)
        
        // Use the 'lightID' of the Lights for comparing. The objects will likely have different 'state' or
        // 'id' values and cannot be relied upon for direct comparisson.
        let lightsNotInGroupIDs = lightsNotInGroup.map({ $0.lightID }).sorted()
        let lightsNotInSceneIDs = lightsNotInScene.map({ $0.lightID }).sorted()
        
        do {
            for (lightItem) in sceneLights {
                // Ignore lights that don't belong to the Scene's Group
                if (lightsNotInGroupIDs.contains(lightItem.lightID)) { continue }
                
                // Add the Light to the Scene if it doesn't already belong to it and has a state
                if (lightsNotInSceneIDs.contains(lightItem.lightID) && lightItem.state == "ADD") {
                    let lightState = try await deconzClient.getLightState(lightID: lightItem.lightID)
                    let _ = try await deconzClient.modifyScene(groupID: groupID, sceneID: sceneID, lightIDs: [lightItem.lightID], state: lightState)
                }
                
                // Remove the Light from the Scene if it already belongs to it and doesn't have a state
                if (!lightsNotInSceneIDs.contains(lightItem.lightID) && lightItem.state == "REMOVE") {
                    let _ = try await deconzClient.modifyScene(groupID: groupID, sceneID: sceneID, lightIDs: [lightItem.lightID], state: nil)
                }
            }
        } catch {
            // FIXME: Handle errors
            print(error)
        }
        
        Task {
            await refreshLightsList(forGroupID: groupID, sceneID: nil)
        }
    }
    
    func modifyScene(range: ModifySceneRange) async {
        guard let selectedSidebarItem = selectedSidebarItem,
              let groupID = selectedSidebarItem.groupID,
              let sceneID = selectedSidebarItem.sceneID
        else { return }
        
        let lightIDs: [Int]
        switch range {
        case .allLightsInScene:
            lightIDs = self.lightsList.map({ $0.lightID }).sorted()
        case .selectedLightsOnly:
            lightIDs = selectedLightItems.map({ $0.lightID }).sorted()
        }
        
        guard let lightState: deCONZLightState = try? decoder.decode(deCONZLightState.self, from: jsonStateText.data(using: .utf8)!),
              let _ = try? await deconzClient.modifyScene(groupID: groupID, sceneID: sceneID, lightIDs: lightIDs, state: lightState)
        else {
            // FIXME: Handle errors
            print("Error Updating Group \(groupID), Scene \(sceneID), Lights \(lightIDs)")
            return
        }
        
        // If the request was successful, store the new JSON state in the modified lights
        var sceneLightsCopy = self.lightsList
        for (lightID, _) in lightIDs.enumerated() {
            sceneLightsCopy[lightID].state = jsonStateText
        }
        
        let list = sceneLightsCopy
        await MainActor.run {
            self.lightsList = list
        }
    }
    
    func deleteScene(groupID: Int, sceneID: Int) async {
        do {
            try await deconzClient.deleteScene(groupID: groupID, sceneID: sceneID)
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
        } catch {
            // FIXME: Handle errors
            print(error)
        }
        
        Task {
            await refreshSidebarItems()
        }
    }
}
