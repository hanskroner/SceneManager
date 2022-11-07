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
        
        // Ignore Groups where 'devicemembership' is not empty
        // These groups are created by switches or sensors and are not the kind we're looking for.
        let filteredGroups = cacheGroups.filter({ $0.value.devicemembership?.isEmpty ?? true })
        
        for (_, group) in filteredGroups {
            guard let groupName = group.name,
                  let groupStringID = group.id,
                  let groupID = Int(groupStringID),
                  let scenes = group.scenes
            else { return }
            
            // FIXME: Will have to check 'isExpanded' against previously saved 'oldValue's when refreshing.
            //        The Model stores the expanded states of the View's DisclosureGroups in the List Model's
            //        'isExpanded' property. These will all be 'false' when creating the new SidebarItems.
            //        If there are previous entries in the List Model, the values of 'isExpanded' should be
            //        copied across to the new list. Otherwise the View will collapse all DisclosureGroups
            //        after the redraw.
            var groupItem = SidebarItem(id: "G\(groupID)", name: groupName, groupID: groupID)
            
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
                  let lightName = light.name,
                  let lightState = sceneAttributes[lightID]
            else { return }
            
            let stateString = lightState.prettyPrint
            updatedSceneLights.append(SceneLight(id: "G\(groupID)S\(sceneID)L\(lightID)", lightID: lightID, name: lightName, state: stateString))
        }
        
        // Sort Light names alphabetically
        let list = updatedSceneLights.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        await MainActor.run {
            self.sceneLights = list
        }
    }
    
    // MARK: - deCONZ CRUD Methods
    
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
        
        guard let _ = try? await deconzClient.modifyScene(groupID: groupID, sceneID: sceneID, lightIDs: lightIDs, state: jsonStateText) else {
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
    
    func createNewSidebarItem() async {
        // In keeping with modern macOS design, a Group is created immediately using a proposed name
        // instead of presenting a Window to the user and asking them to name the Group. The code below
        // doesn't actually create a new Group via the REST API, instead it inserts a SidebarItem in the
        // Model's List Model which is immediately ready to rename. Once the rename is performed, the View
        // will call on the Model to create the Group via the REST API.
        
        // First, go through the existing Group names and propose an un-used placeholder name for the new
        // Group that. The REST API will produce an error when attempting to create a new Group with an
        // already-existing name - this is just to make the creation process friendlier.
        let groupNames = sidebarItems.compactMap({ $0.name })
        let proposedName = "New Group"
        var proposedNameSuffix = ""
        
        for index in 1 ..< 100 {
            if !groupNames.contains(proposedName + proposedNameSuffix) { break }
            proposedNameSuffix = String(index)
        }
        
        let newGroupName = proposedName + proposedNameSuffix
        
        // The SidebarItem for the new group is created with '-999' as its GroupID. It is also flagged as
        // 'renaming' and 'wantingFocus' to have the View draw it as a TextField with focus - allowing the
        // user to immediately provide the actual name for the new group. The View identifies items with
        // GroupID '-999' as "new" and routes the submission after renaming to "createGroup" instead of the
        // usual "renameGroup". The flags are temporary, as this SidebarItem will be released when the Model's
        // List Model is refreshed after performing the actual group creation via the REST API.
        
        let newGroupID = -999
        let newGroupItem = SidebarItem(id: newGroupName, name: newGroupName, groupID: newGroupID, isRenaming: true, wantsFocus: true)
        await MainActor.run {
            // The SidebarItem representing the new group is added to the Model's List Model. The List Model
            // is then sorted before being presented again to the user. Finally, the newly created SidebarItem
            // is scrolled into view.
            var mutableCopy = self.sidebarItems
            mutableCopy.append(newGroupItem)
            self.sidebarItems = mutableCopy.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            self.scrollToItem = newGroupName
        }
    }
    
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
}
