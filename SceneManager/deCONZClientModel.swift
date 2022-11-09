//
//  deCONZClientModel.swift
//  SceneManager
//
//  Created by Hans Kröner on 06/11/2022.
//

import SwiftUI

enum ModifySceneRange {
    case allLightsInGroup
    case selectedLightsOnly
}

class deCONZClientModel: ObservableObject {
    private let deconzClient = deCONZClient()
    
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    @Published var selectedSidebarItem: SidebarItem? = nil {
        didSet {
            if (oldValue != selectedSidebarItem) {
                self.selectedSceneLights.removeAll()
            }
            
            if (selectedSidebarItem == nil) {
                self.sceneLights = [SceneLight]()
            }
            
            if let groupID = selectedSidebarItem?.groupID, let sceneID = selectedSidebarItem?.sceneID {
                Task {
                    await self.updateSceneLights(forGroupID: groupID, sceneID: sceneID)
                }
            }
        }
    }
    
    @Published var selectedSceneLights = Set<SceneLight>()
    
    @Published var jsonStateText = ""
    
    @Published var scrollToItem: String? {
        didSet {
            prepareListSnapshot()
        }
    }
    
    @Published var sidebarItems = [SidebarItem]()
    @Published var sceneLights = [SceneLight]()

    private var cacheLights: [Int: deCONZLight]?
    private var cacheGroups: [Int: deCONZGroup]?
    private var cacheScenes: [Int: [Int: deCONZScene]]?

    private var copyForSnapshot: [SidebarItem]?

    init() {
        Task {
            self.cacheLights = try await deconzClient.getAllLights()
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
            
            Task {
                await refreshSidebarItems()
            }
        }
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
        
        // Ignore Groups where 'devicemembership' is not empty
        // These groups are created by switches or sensors and are not the kind we're looking for.
        let filteredGroups = cacheGroups.filter({ $0.value.devicemembership?.isEmpty ?? true })
        
        for (_, group) in filteredGroups {
            guard let groupName = group.name,
                  let groupStringID = group.id,
                  let groupID = Int(groupStringID),
                  let scenes = group.scenes
            else { return }
            
            var groupItem = SidebarItem(id: "G\(groupID)", name: groupName, groupID: groupID, isExpanded: storedExpansions[groupID] ?? false)
            
            for (sceneStringID) in scenes {
                guard let sceneID = Int(sceneStringID),
                      let sceneName = cacheScenes[groupID]?[sceneID]?.name
                else { return }
                
                let sceneItem = SidebarItem(id: "G\(groupID)S\(sceneID)", name: sceneName, parentName: groupName, groupID: groupID, sceneID: sceneID)
                
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
    
    private func updateSceneLights(forGroupID groupID: Int, sceneID: Int) async {
        var updatedSceneLights = [SceneLight]()
        
        let sceneAttributes = try? await deconzClient.getSceneAttributes(groupID: groupID, sceneID: sceneID)
        
        guard let cacheLights = self.cacheLights,
              let cacheGroups = self.cacheGroups,
              let sceneAttributes = sceneAttributes
        else { return }
        
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        
        for (stringLightID) in cacheGroups[groupID]?.lights ?? [] {
            guard let lightID = Int(stringLightID),
                  let light = cacheLights[lightID],
                  let lightName = light.name
            else { return }
            
            guard let lightState = sceneAttributes[lightID] else {
                // The light is in the group, but not in the scene. This is one of the two possible outcomes
                // after modifying the light members of a group. In order to add the light to the scene, a
                // call to 'storeScene' is needed. This will overwrite the saved states of all the other
                // lights in the scene, so they'll need to be restored.
                print("[Group ID \(groupID), Scene ID \(sceneID)] - No Attributes for Light ID \(lightID)")
                fatalError("WIP")
            }
            
            let stateString = lightState.prettyPrint
            updatedSceneLights.append(SceneLight(id: "G\(groupID)S\(sceneID)L\(lightID)", lightID: lightID, name: lightName, state: stateString))
        }
        
        // Sort Light names alphabetically
        let list = updatedSceneLights.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        await MainActor.run {
            self.sceneLights = list
        }
    }
    
    func lightsNotIn(groupID: Int) -> [SceneLight] {
        var missingSceneLights = [SceneLight]()
        
        guard let cacheLights = self.cacheLights,
              let cacheGroups = self.cacheGroups,
              let groupLights = cacheGroups[groupID]?.lights
        else { return [SceneLight]() }
        
        let groupLightsIDs = groupLights.compactMap({ Int($0) })
        let lighstNotInGroup = cacheLights.filter({ !groupLightsIDs.contains($0.0) })
        for (lightID, lightNotInGroup) in lighstNotInGroup {
            missingSceneLights.append(SceneLight(id: "ADD\(groupID)L\(lightID)", lightID: lightID, name: lightNotInGroup.name!, state: ""))
        }
        
        return missingSceneLights.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
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
    
    func modifyGroupLights(groupID: Int, groupLights: [SceneLight]) async {
        let groupLightsIDs = groupLights.map({ $0.lightID }).sorted()
        
        // Modifying the Lights in a Group is a more expensive operation that one wouuld think at first
        // glace. Naively calling only 'setGroupAttributes' with the new Lights the group should have leaves
        // the Scenes in an inconsistent state - a deCONZ Groups has a list of the Lights in it, but Scenes
        // of a Group are just a list of Lights with specific State Attributes. Modifying the list of Lights
        // in a Group needs to also modify all of its Scenes so that the list of Lights across all of them
        // is the same.
        // There is no 'setSceneAttributes' in deCONZ that allows for modifying the Lights memebers of a
        // Scene. Instead, 'storeScene' needs to be called - which will instruct the Lights to store their
        // current State Attributes as the Scene for a given identifier. This works fine for the interactive
        // way the deCONZ UI, Phoscon, builds Scenes but not for us - our goal is to be able to create and
        // update Scenes without affecting the current State Attributes of Lights.
        // In order to keep the list of Lights across a Group and its Scenes in sync, all Scenes in a Group
        // will have to be rebuilt when the list of Lights in a Group changes. First, the Group's Lights are
        // updated by calling 'setGroupAttributes', a copy of the current Scenes cache is made and the
        // cache of Groups and Scenes is refreshed. Next, for each of a Group's Scenes, 'storeScene' is
        // called - syncing the list of Lights in the Group with that Scene, but also over-writting the
        // State Attibutes of all the Lights with their current state. The previous State Attributes for each
        // Light in the Scene can be looked up in the copy that was made of the Scenes cache, and then
        // applied to each Light by calling 'modifyScene' on each one.
        // Depending on the number of Lights and Scenes in a Group, this operation can take a while. To make
        // matters worse, the deCONZ REST API doesn't have a throttling mechanism for requests - sending
        // requests "too fast" will lead to error and lost packets, so a 500ms delay between requests is
        // inserted. This means that an operation on a Group with 10 Lights and 5 Scenes will take roughly
        // 25 seconds to complete.
        // TODO: Consider the possibility of queueing the above commands
        //       The idea would be to send commands as fast as posible until an error is returned. That would
        //       introduce a wait, after which the queued commands would again be sent as fast as possible
        //       until another error is returned.
        
        do {
            let cacheScenesCopy = self.cacheScenes
            var sceneAttributesCopy = [Int: [Int: deCONZLightState]]()
            for (sceneID, _) in cacheScenesCopy?[groupID] ?? [:] {
                sceneAttributesCopy[sceneID] = try await deconzClient.getSceneAttributes(groupID: groupID, sceneID: sceneID)
            }
            
            try await deconzClient.setGroupAttributes(groupID: groupID, lights: groupLightsIDs)
            
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
            
            // Sync the Lights in each Scene to the new Lights in the Group by calling 'storeScene'
            for (sceneID, scene) in self.cacheScenes?[groupID] ?? [:] {
                try await deconzClient.storeScene(groupID: groupID, sceneID: sceneID)
                
                // Restore the State Attributes each Light in each Scene had before being overwritten by
                // the previous call to 'storeScene'
                for lightID in scene.lights?.compactMap({ Int($0) }) ?? [] {
                    let storedState = sceneAttributesCopy[sceneID]?[lightID] ?? deCONZLightState()
                    try await deconzClient.modifyScene(groupID: groupID, sceneID: sceneID, lightIDs: [lightID], state: storedState)
                }
            }
        } catch {
            // FIXME: Handle errors
            print(error)
        }
        
        Task {
            await updateSceneLights(forGroupID: groupID, sceneID: self.selectedSidebarItem!.sceneID!)
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
    
    func modifyScene(range: ModifySceneRange) async {
        guard let selectedSidebarItem = selectedSidebarItem,
              let groupID = selectedSidebarItem.groupID,
              let sceneID = selectedSidebarItem.sceneID
        else { return }
        
        let lightIDs: [Int]
        switch range {
        case .allLightsInGroup:
            lightIDs = self.sceneLights.map({ $0.lightID }).sorted()
        case .selectedLightsOnly:
            lightIDs = selectedSceneLights.map({ $0.lightID }).sorted()
        }
        
        guard let lightState: deCONZLightState = try? decoder.decode(deCONZLightState.self, from: jsonStateText.data(using: .utf8)!),
              let _ = try? await deconzClient.modifyScene(groupID: groupID, sceneID: sceneID, lightIDs: lightIDs, state: lightState)
        else {
            // FIXME: Handle errors
            print("Error Updating Group \(groupID), Scene \(sceneID), Lights \(lightIDs)")
            return
        }
        
        // If the request was successful, store the new JSON state in the modified lights
        var sceneLightsCopy = self.sceneLights
        for (lightID, _) in lightIDs.enumerated() {
            sceneLightsCopy[lightID].state = jsonStateText
        }
        
        let list = sceneLightsCopy
        await MainActor.run {
            self.sceneLights = list
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
