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
    
    var hasWarning: Bool = false
    var isShowingWarning: Bool = false
    var warningTitle: String? = nil
    var warningBody: String? = nil
    
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
    
    // MARK: - Warning Methods
    
    func showWarningPopover(title: String, body: String) {
        self.warningTitle = title
        self.warningBody = body
        
        self.hasWarning = true
        self.isShowingWarning = true
    }
    
    func clearWarnings() {
        self.isShowingWarning = false
        self.hasWarning = false
        
        self.warningTitle = nil
        self.warningBody = nil
    }
    
    func handleError(_ error: any Error) {
        var warningTitle = "Error"
        var warningBody = "Unknown Error"
        
        // Errors related to JSON decoding
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .dataCorrupted(let context):
                warningTitle = context.debugDescription.replacingOccurrences(of: ".", with: "")
                if let nsError = context.underlyingError as NSError? {
                    warningBody = nsError.userInfo["NSDebugDescription"] as? String ?? "Unknown Error"
                }
                
            case .keyNotFound(let codingKey, _):
                warningTitle = "Missing required keys in JSON"
                warningBody = "No value associated with key \"\(codingKey.stringValue)\""
                
            case .typeMismatch(_, let context):
                warningTitle = "Value mismatch in JSON"
                warningBody = context.debugDescription.replacingOccurrences(of: ".", with: "") + " for key \"\(context.codingPath.first?.stringValue ?? "")\"."
                
            default:
                break
            }
        }
        
        // Errors related to the deCONZ REST API
        if let apiError = error as? APIError {
            switch apiError {
            case .apiError(let context):
                warningTitle = "deCONZ REST API Error"
                warningBody = context.description
                
            default:
                break
            }
        }

        showWarningPopover(title: warningTitle, body: warningBody)
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
            return
        }
        
        // Scene lights
        let newItems = RESTModel.shared.scene(withGroupId: groupId, sceneId: sceneId)!.lightIds.map({
            LightItem(light: RESTModel.shared.light(withLightId: $0)!)
        })
        
        self.lights?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    
    // MARK: - Light State Methods
    
    func jsonLightState(forLightId lightId: Int, groupId: Int? = nil, sceneId: Int? = nil) async throws -> String {
        return try await RESTModel.shared.lightState(withLightId: lightId, groupId: groupId, sceneId: sceneId)
    }
    
    func jsonDynamicState(forGroupId groupId: Int? = nil, sceneId: Int? = nil) async throws -> String {
        return try await RESTModel.shared.dynamicState(withGroupId: groupId, sceneId: sceneId)
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
    
    func add(lightIds: [Int], toGroupId groupId: Int) async throws {
        try await RESTModel.shared.addLightsToGroup(groupId: groupId, lightIds: lightIds)
        
        // Update UI models
        let addedItems = lightIds.map({
            LightItem(light: RESTModel.shared.light(withLightId: $0)!)
        })
        
        let newItems = Array(Set([self.lights?.items ?? [], addedItems].joined()))
        self.lights?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    
    func add(lightIds: [Int], toGroupId groupId: Int, sceneId: Int) async throws {
        try await RESTModel.shared.addLightsToScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds)
        
        // Update UI models
        let addedItems = lightIds.map({
            LightItem(light: RESTModel.shared.light(withLightId: $0)!)
        })
        
        let newItems = Array(Set([self.lights?.items ?? [], addedItems].joined()))
        self.lights?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    
    func remove(lightIds: [Int], fromGroupId groupId: Int) async throws {
        try await RESTModel.shared.removeLightsFromGroup(groupId: groupId, lightIds: lightIds)
        
        // Update UI models
        let newItems = self.lights?.items.filter { !lightIds.contains($0.lightId) } ?? []
        self.lights?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    
    func remove(lightIds: [Int], fromGroupId groupId: Int, sceneId: Int) async throws {
        try await RESTModel.shared.removeLightsFromScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds)
        
        // Update UI models
        let newItems = self.lights?.items.filter { !lightIds.contains($0.lightId) } ?? []
        self.lights?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    
    // MARK: - Group Methods
    
    func turnOff(groupId: Int) async throws {
        try await RESTModel.shared.modifyGroupState(groupId: groupId, lightState: LightState(on: false))
        
        // No need to update UI models - they don't track the state of lights
    }
    
    // MARK: - Scene Methods
    
    func applyState(_ state: PresetStateDefinition, toGroupId groupId: Int, sceneId: Int, lightIds: [Int]) async throws {
        do {
            switch state {
            case .recall(_):
                return try await RESTModel.shared.modifyLightStateInScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds, jsonLightState: state.json.prettyPrint())
                
            case .dynamic(_):
                return try await RESTModel.shared.applyDynamicStatesToScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds, jsonDynamicState: state.json.prettyPrint())
            }
        }
    }
    
    func recall(groupId: Int, sceneId: Int) async throws {
        try await RESTModel.shared.recallScene(groupId: groupId, sceneId: sceneId)
        // No need to update UI models - they don't track the state of lights
    }
}
