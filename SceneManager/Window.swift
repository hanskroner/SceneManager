//
//  Window.swift
//  SceneManager
//
//  Created by Hans Kröner on 13/11/2024.
//

import SwiftUI
import Combine
import OSLog

import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "window")

@Observable
class WindowItem {
    weak var sidebar: Sidebar? = nil
    weak var lights: Lights? = nil
    
    var navigationTitle: String? = nil
    var navigationSubtitle: String? = nil
    
    var groupId: Int? = nil
    var sceneId: Int? = nil
    
    var selectedEditorTab: Tab = .sceneState
    var stateEditorText: String = ""
    var dynamicsEditorText: String = ""
    
    var modelRefreshedSubscription: AnyCancellable? = nil
        
    init() {
        modelRefreshedSubscription = RESTModel.shared.onDataRefreshed.sink { [weak self] _ in
            // Clear this WindowItem's state
            self?.navigationTitle = nil
            self?.navigationSubtitle = nil
            self?.groupId = nil
            self?.sceneId = nil
            self?.selectedEditorTab = .sceneState
            self?.stateEditorText = ""
            self?.dynamicsEditorText = ""
            
            let groups = RESTModel.shared.groups
            
            var newItems = [SidebarItem]()
            for group in groups {
                let groupItem = SidebarItem(name: group.name, groupId: group.groupId)
                for sceneId in group.sceneIds {
                    let scene = RESTModel.shared.scene(withGroupId: group.groupId, sceneId: sceneId)!
                    let sceneItem = SidebarItem(name: scene.name, groupId: group.groupId, sceneId: sceneId)
                    groupItem.items.append(sceneItem)
                }
                
                groupItem.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                newItems.append(groupItem)
            }
            
            self?.sidebar?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            self?.updateLights(forGroupId: self?.groupId, sceneId: self?.sceneId)
        }
    }
    
    // MARK: - Update Methods
    
    func updateLights(forGroupId groupId: Int?, sceneId: Int?) {
        // No lights
        guard let groupId else {
            self.lights?.items = []
            return
        }
        
        // Group lights
        guard let sceneId else {
            let newItems = RESTModel.shared.group(withGroupId: groupId)!.lightIds.map({
                LightItem(light: RESTModel.shared.light(withLightId: $0)!)
            })
            self.lights?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            
            let ids = Array(self.lights!.selectedLightItemIds)
            logger.info("Selection is '\(ids, privacy: .public)'")
            
            return
        }
        
        // Scene lights
        let newItems = RESTModel.shared.scene(withGroupId: groupId, sceneId: sceneId)!.lightIds.map({
            LightItem(light: RESTModel.shared.light(withLightId: $0)!)
        })
        self.lights?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        
        let ids = Array(self.lights!.selectedLightItemIds)
        let avail = self.lights!.items.map { $0.id }
        logger.info("Selection is '\(ids, privacy: .public)'")
        logger.info("Available are '\(avail, privacy: .public)'")
    }
    
    // MARK: - Light State Methods
    
    func jsonLightState(forLightId lightId: Int, groupId: Int? = nil, sceneId: Int? = nil) async -> String {
        return await RESTModel.shared.lightState(withLightId: lightId, groupId: groupId, sceneId: sceneId)
    }
    
    func jsonDynamicState(forGroupId groupId: Int? = nil, sceneId: Int? = nil) async -> String {
        return await RESTModel.shared.dynamicState(withGroupId: groupId, sceneId: sceneId)
    }
    
    // MARK: - Light Methods
    
    func lights(inGroupId groupId: Int) -> [Light] {
        let groupLightIds = RESTModel.shared.group(withGroupId: groupId)?.lightIds ?? []
        return RESTModel.shared.lights.filter { groupLightIds.contains($0.lightId) }
    }
    
    func lights(notInGroupId groupId: Int) -> [Light] {
        let groupLightIds = RESTModel.shared.group(withGroupId: groupId)?.lightIds ?? []
        return RESTModel.shared.lights.filter { !groupLightIds.contains($0.lightId) }
    }
    
    func lights(inGroupId groupId: Int, sceneId: Int) -> [Light] {
        let sceneLightIds = RESTModel.shared.scene(withGroupId: groupId, sceneId: sceneId)?.lightIds ?? []
        return RESTModel.shared.lights.filter { sceneLightIds.contains($0.lightId) }
    }
    
    func lights(inGroupId groupId: Int, butNotIntSceneId sceneId: Int) -> [Light] {
        let groupLightIds = RESTModel.shared.group(withGroupId: groupId)?.lightIds ?? []
        let sceneLightIds = RESTModel.shared.scene(withGroupId: groupId, sceneId: sceneId)?.lightIds ?? []
        let inGroupButNotInSceneLightIds = groupLightIds.filter { !sceneLightIds.contains($0) }
        
        return RESTModel.shared.lights.filter { inGroupButNotInSceneLightIds.contains($0.lightId) }
    }
    
    func add(lightIds: [Int], toGroupId groupId: Int) {
        Task {
            do {
                try await RESTModel.shared.addLightsToGroup(groupId: groupId, lightIds: lightIds)
            } catch {
                // FIXME: Error handling
                logger.error("\(error, privacy: .public)")
                return
            }
            
            // Update UI models
            let addedItems = lightIds.map({
                LightItem(light: RESTModel.shared.light(withLightId: $0)!)
            })
            
            let newItems = Array(Set([self.lights?.items ?? [], addedItems].joined()))
            self.lights?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
    
    func add(lightIds: [Int], toGroupId groupId: Int, sceneId: Int) {
        Task {
            do {
                try await RESTModel.shared.addLightsToScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds)
            } catch {
                // FIXME: Error handling
                logger.error("\(error, privacy: .public)")
                return
            }
            
            // Update UI models
            let addedItems = lightIds.map({
                LightItem(light: RESTModel.shared.light(withLightId: $0)!)
            })
            
            let newItems = Array(Set([self.lights?.items ?? [], addedItems].joined()))
            self.lights?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
    
    func remove(lightIds: [Int], fromGroupId groupId: Int) {
        Task {
            do {
                try await RESTModel.shared.removeLightsFromGroup(groupId: groupId, lightIds: lightIds)
            } catch {
                // FIXME: Error handling
                logger.error("\(error, privacy: .public)")
                return
            }
            
            // Update UI models
            let newItems = self.lights?.items.filter { !lightIds.contains($0.lightId) } ?? []
            self.lights?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
    
    func remove(lightIds: [Int], fromGroupId groupId: Int, sceneId: Int) {
        Task {
            do {
                try await RESTModel.shared.removeLightsFromScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds)
            } catch {
                // FIXME: Error handling
                logger.error("\(error, privacy: .public)")
                return
            }
            
            // Update UI models
            let newItems = self.lights?.items.filter { !lightIds.contains($0.lightId) } ?? []
            self.lights?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
    
    // MARK: - Group Methods
    
    func turnOff(groupId: Int) {
        Task {
            await RESTModel.shared.modifyGroupState(groupId: groupId, lightState: LightState(on: false))
            
            // FIXME: Update UI models
            //        Turning a group off would update its state
        }
    }
    
    // MARK: - Scene Methods
    
    func applyState(_ state: PresetStateDefinition, toGroupId groupId: Int, sceneId: Int, lightIds: [Int]) {
        Task {
            do {
                switch state {
                case .recall(_):
                    return try await RESTModel.shared.modifyLightStateInScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds, jsonLightState: state.json.prettyPrint())
                    
                case .dynamic(_):
                    return try await RESTModel.shared.applyDynamicStatesToScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds, jsonDynamicState: state.json.prettyPrint())
                }
            } catch {
                // FIXME: Error handling
                logger.error("\(error, privacy: .public)")
                return
            }
        }
    }
    
    func recall(groupId: Int, sceneId: Int) {
        Task {
            await RESTModel.shared.recallScene(groupId: groupId, sceneId: sceneId)
        }
        
        // FIXME: Update UI models
        //        Recalling a scene would update its group's state
    }
}
