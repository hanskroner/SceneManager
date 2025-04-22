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

struct FocusedWindowItem: FocusedValueKey {
    typealias Value = WindowItem
}

extension FocusedValues {
    var activeWindow: FocusedWindowItem.Value? {
        get { self[FocusedWindowItem.self] }
        set { self[FocusedWindowItem.self] = newValue }
    }
}


@MainActor
@Observable
class WindowItem {
    weak var sidebar: Sidebar? = nil
    weak var lights: Lights? = nil
    
    var groupId: Int? = nil
    var sceneId: Int? = nil
    
    // Navigation Bar
    var navigationTitle: String? = nil
    var navigationSubtitle: String? = nil
    
    // State editors
    var selectedEditorTab: Tab = .sceneState
    var stateEditorText: String = ""
    var dynamicsEditorText: String = ""
    
    // Warning indicator
    var hasWarning: Bool = false
    var isShowingWarning: Bool = false
    var warningTitle: String? = nil
    var warningBody: String? = nil
    
    // Menu Bar actions
    var isPresentingStartupConfiguration = false
    var isPresentingPhosconDelete = false
    var phosconKeys: [String] = []
    
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
            
            // Keep any SidebarItem UUIDs that are expanded to restore their state later
            let expandedIds = self?.sidebar?.items.compactMap({ $0.isExpanded ? $0.id : nil }) ?? []
            let sidebarSelection = self?.sidebar?.selectedSidebarItemId
            
            let groups = RESTModel.shared.groups
            
            var newItems = [SidebarItem]()
            for group in groups {
                let groupItem = SidebarItem(name: group.name, groupId: group.groupId)
                groupItem.isExpanded = expandedIds.contains(groupItem.id)
                for sceneId in group.sceneIds {
                    let scene = RESTModel.shared.scene(withGroupId: group.groupId, sceneId: sceneId)!
                    let sceneItem = SidebarItem(name: scene.name,
                                                groupId: group.groupId,
                                                sceneId: sceneId,
                                                hasDynamics: scene.dynamicState != nil)
                    groupItem.items.append(sceneItem)
                }
                
                groupItem.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                newItems.append(groupItem)
            }
            
            Task { @MainActor in
                // Try to restore selections safely
                if let sidebarSelection {
                    // Check to see if the selected item exists in the new items
                    var selectedItem: SidebarItem? = nil
                    for item in newItems {
                        if item.id == sidebarSelection { selectedItem = item; break }
                        if let child = item.items.first(where: { $0.id == sidebarSelection }) { selectedItem = child; break }
                    }
                    
                    // Restore selection only if it exists in the new items
                    if let selectedItem  {
                        self?.groupId = selectedItem.groupId
                        self?.sceneId = selectedItem.sceneId
                    } else {
                        self?.sidebar?.selectedSidebarItemId = nil
                        self?.lights?.selectedLightItemIds.removeAll()
                    }
                }
                
                self?.sidebar?.items = newItems.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                self?.updateLights(forGroupId: self?.groupId, sceneId: self?.sceneId)
            }
        }
    }
    
    // MARK: - Warning Methods
    
    @MainActor
    func showWarningPopover(title: String, body: String) {
        self.warningTitle = title
        self.warningBody = body
        
        self.hasWarning = true
        self.isShowingWarning = true
    }
    
    @MainActor
    func clearWarnings() {
        self.isShowingWarning = false
        self.hasWarning = false
        
        self.warningTitle = nil
        self.warningBody = nil
    }
    
    @MainActor func handleError(_ error: any Error) {
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
        
        // Errors related to NSURL
        if let urlError = error as? URLError {
            switch urlError {
            default:
                warningTitle = "deCONZ REST API Connection Error"
                warningBody = urlError.localizedDescription
            }
        }
        
        // Errors related to the deCONZ REST API
        if let apiError = error as? APIError {
            switch apiError {
            case .apiError(let context):
                warningTitle = "deCONZ REST API Error"
                warningBody = ""
                for (index, error) in context.enumerated() {
                    warningBody += "address: \(error.address)\ndescription: \(error.description)\(index == context.count - 1 ? "" : "\n\n")"
                }
                
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
    
    func updateEditors(selectedGroupId groupId: Int?, selectedSceneId sceneId: Int?, selectedLightIds: [Int]) async throws {
        // Group selection
        if let groupId, sceneId == nil {
            if let selectedLightId = selectedLightIds.first {
                // At least one light was selected
                //   State Editor shows light state
                //   Dynamics Editor is cleared
                //   State Editor tab is selected
                let lightState = try await RESTModel.shared.lightState(withLightId: selectedLightId,
                                                             groupId: groupId)

                if ((lightState != "") && (self.selectedEditorTab != .sceneState)) {
                    self.selectedEditorTab = .sceneState
                }
                
                self.stateEditorText = lightState
                self.dynamicsEditorText = ""
                
                return
            } else {
                // No lights are selected
                //   Clear out both Editors
                self.stateEditorText = ""
                self.dynamicsEditorText = ""
                return
            }
        }
        
        // Scene selection
        if let groupId, let sceneId {
            if let selectedLightId = selectedLightIds.first {
                // At least one light was selected
                //   State Editor shows light state for scene
                //   Dynamics Editor shows dynamic scene
                //   State Editor tab is selected only if dynamics is empty
                let sceneState = try await RESTModel.shared.sceneState(forLightId: selectedLightId,
                                                                       groupId: groupId,
                                                                       sceneId: sceneId)
                
                if ((sceneState.1 == "") && (self.selectedEditorTab != .sceneState)) {
                    self.selectedEditorTab = .sceneState
                }
                
                self.stateEditorText = sceneState.0
                self.dynamicsEditorText = sceneState.1
                
                return
            } else {
                // No lights are selected
                //   State Editor is cleared
                //   Dynamics Editor shows dynamic scene
                //   Dynamics Editor tab is selected only if dynamics is not empty
                let dynamicState = try await RESTModel.shared.dynamicState(withGroupId: groupId,
                                                                           sceneId: sceneId)
                
                if ((dynamicState != "") && (self.selectedEditorTab != .dynamicScene)) {
                    self.selectedEditorTab = .dynamicScene
                }
                
                self.stateEditorText = ""
                self.dynamicsEditorText = dynamicState
                
                return
            }
        }
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
    
    // MARK: - Scene Methods
    
    func applyState(_ state: PresetStateDefinition, toGroupId groupId: Int, sceneId: Int, lightIds: [Int]) async throws {
        do {
            switch state {
            case .recall(_):
                return try await RESTModel.shared.modifyLightStateInScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds, jsonLightState: state.json.prettyPrint())
                
            case .dynamic(_):
                try await RESTModel.shared.applyDynamicStatesToScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds, jsonDynamicState: state.json.prettyPrint())
                
                // Update UI models
                // Updating a dynamic scene needs to be reflected in the Sidebar model
                if let sidebarItem = self.sidebar?.sidebarItem(forGroupId: groupId, sceneId: sceneId) {
                    sidebarItem.hasDynamics = true
                }
                
                return
            }
        }
    }
    
    func deleteDynamicScene(fromGroupId groupId: Int, sceneId: Int) async throws {
        try await RESTModel.shared.deleteDynamicStatesFromScene(groupId: groupId, sceneId: sceneId)
        
        // Update UI models
        // Updating a dynamic scene needs to be reflected in the Sidebar model
        if let sidebarItem = self.sidebar?.sidebarItem(forGroupId: groupId, sceneId: sceneId) {
            sidebarItem.hasDynamics = false
        }
        
        // If this scene is currently selected, clear the value of the Dynamics Editor
        if (self.groupId == groupId && self.sceneId == sceneId) {
            self.dynamicsEditorText = ""
            self.selectedEditorTab = .sceneState
        }
        
    }
}
