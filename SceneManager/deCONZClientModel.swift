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
    
    @Published private(set) var sidebarItems = [SidebarItem]()
    @Published private(set) var sceneLights = [SceneLight]()
    
    private var cacheLights: [Int: deCONZLight]?
    private var cacheGroups: [Int: deCONZGroup]?
    private var cacheScenes: [Int: [Int: deCONZScene]]?
    
    init() {
        Task {
            self.cacheLights = try await deconzClient.getAllLights()
            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()
            
            Task {
                await refreshSidebarItems()
            }
        }
    }
    
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
    
    func createNewGroup() async {
        guard let cacheGroups = self.cacheGroups else { return }
        
        // In keeping with modern macOS design, a Group is created immediately using a proposed name
        // instead of presenting a Window to the user and asking them to name the Group. The code below
        // goes through the existing Group names and tries to create a proposed name for the new Group that
        // won't clash with existing names. If it failes to propose a reasonable name, the REST API will
        // produce an error when attempting to create a new Group with an already-existing name.
        
        let groupNames = Array(cacheGroups.values).compactMap({ $0.name })
        let proposedName = "New Group"
        var proposedNameSuffix = ""
        
        for index in 1 ..< 100 {
            if !groupNames.contains(proposedName + proposedNameSuffix) { break }
            proposedNameSuffix = String(index)
        }
        
        let newGroupName = proposedName + proposedNameSuffix
        
        Task {
            guard let _ = try? await deconzClient.createGroup(name: newGroupName) else {
                // FIXME: Handle errors
                print("Error Creating Group \(newGroupName)")
                return
            }

            // To make absolutely sure that the model's knowledge of Groups matches deCONZ's, etch the
            // Group and Scene information from the REST API and update the model's cache. This will trigger
            // SwiftUI to redraw the UI, which will now include the newly-created group. To make the new
            // Group visible to the user, the model will mark it as selected, which will trigger SwiftUI
            // to selected it in the UI.

            (self.cacheGroups, self.cacheScenes) = try await deconzClient.getAllGroups()

            Task {
                await refreshSidebarItems()
                // FIXME: Not working
                // I haven't been able to get this working. The approach seems to be to wrap the List in
                // a ScrollViewReader and then use an 'onChange' view modifier to call scrollTo() on the
                // ScrollViewReader to the new item - except nothing happens. It seems having nested
                // ForEachs or not having set Identifiability correctly is making things not work.
//                let newSidebarItems = sidebarItems.map { item in
//                    if (item.id == "G\(newGroupID)") {
//                        var item = item
//                        item.isRenaming = true
//                        return item
//                    }
//
//                    return item
//                }
//
//                await MainActor.run {
//                    self.sidebarItems = newSidebarItems
//                }
            }

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
