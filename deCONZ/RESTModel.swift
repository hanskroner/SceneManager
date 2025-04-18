//
//  RESTModel.swift
//  SceneManager
//
//  Created by Hans Kröner on 10/11/2024.
//

import Combine
import OSLog

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "rest-model")

@MainActor
@Observable
public final class RESTModel {
    private var _lights: [Int: Light] = [:]
    private var _groups: [Int: Group] = [:]
    private var _scenes: [Int: [Int: Scene]] = [:]
    
    // Combine Publishers
    public let onDataRefreshed = PassthroughSubject<Date, Never>()
    
    private var _client: RESTClient
    public var activity = RESTActivity()
    
    private let _decoder = JSONDecoder()
    private let _encoder = JSONEncoder()
    
    private static var apiKey = UserDefaults.standard.string(forKey: "deconz_key") ?? ""
    private static var apiURL = UserDefaults.standard.string(forKey: "deconz_url") ?? ""
    public static let shared = RESTModel(client: RESTClient.init(apiKey: apiKey, apiURL: apiURL))
    
    private init(client: RESTClient) {
        _encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        _client = client
        
        Task {
            await _client.setActivity(activity)
        }
    }
    
    public func reconnect() {
        RESTModel.apiKey = UserDefaults.standard.string(forKey: "deconz_key") ?? ""
        RESTModel.apiURL = UserDefaults.standard.string(forKey: "deconz_url") ?? ""
        
        Task {
            self._client = RESTClient.init(apiKey: RESTModel.apiKey, apiURL: RESTModel.apiURL)
            await _client.setActivity(activity)
        }
    }
    
    // MARK: Lights
    
    public var lights: [Light] {
        Array(self._lights.values)
    }
    
    public func light(withLightId id: Int) -> Light? {
        return self._lights[id]
    }
    
    public func areHueLights(lightIds: [Int]) -> Bool {
        return areHueLights(lights: lightIds.compactMap({ light(withLightId: $0) }))
    }
    
    public func areHueLights(lights: [Light]) -> Bool {
        let hueLights = lights.filter({ $0.manufacturer.localizedCaseInsensitiveCompare("Philips") == .orderedSame
            || $0.manufacturer.localizedCaseInsensitiveCompare("Signify Netherlands B.V.") == .orderedSame })
        
        return lights.count == hueLights.count
    }
    
    // MARK: Light State
    
    // TODO: Consider different return from 'String'
    public func lightState(withLightId lightId: Int, groupId: Int? = nil, sceneId: Int? = nil) async throws -> String {
        // Current state of the light
        guard let groupId, let sceneId else {
            let state = try await self._client.getLightState(lightID: lightId)
            let encoded = try _encoder.encode(state)
            let decoded = try _decoder.decode(JSON.self, from: encoded)
            
            return decoded.prettyPrint()
        }
        
        // State defined in a scene
        let attributes = try await self._client.getSceneAttributes(groupID: groupId, sceneID: sceneId)
        guard let state = attributes?.lights.filter({ $0.key == lightId }).first?.1 else { return "" }
        let encoded = try _encoder.encode(state)
        let decoded = try _decoder.decode(JSON.self, from: encoded)
        
        return decoded.prettyPrint()
    }
    
    // TODO: Consider different return from 'String'
    public func sceneState(forLightId lightId: Int, groupId: Int, sceneId: Int) async throws -> (String, String) {
        let attributes = try await self._client.getSceneAttributes(groupID: groupId, sceneID: sceneId)
        
        let recallString: String
        if let recallState = attributes?.lights[lightId] {
            recallString = try _decoder.decode(JSON.self, from: try _encoder.encode(recallState)).prettyPrint()
        } else {
            recallString = ""
        }
        
        let dynamicString: String
        if let dynamicState = attributes?.dynamics {
            dynamicString = try _decoder.decode(JSON.self, from: try _encoder.encode(dynamicState)).prettyPrint()
        } else {
            dynamicString = ""
        }
        
        return (recallString, dynamicString)
    }
    
    // TODO: Consider different return from 'String'
    public func dynamicState(withGroupId groupId: Int, sceneId: Int) async throws -> String {
        let attributes = try await self._client.getSceneAttributes(groupID: groupId, sceneID: sceneId)
        guard let state = attributes?.dynamics else { return "" }
        
        let encoded = try _encoder.encode(state)
        let decoded = try _decoder.decode(JSON.self, from: encoded)
        
        return decoded.prettyPrint()
    }
    
    // MARK: Groups
    
    public func createGroup(name: String) async throws -> Int {
        let groupId = try await self._client.createGroup(name: name)
        
        // Insert a new, empty Group into the model's cache
        self._groups[groupId] = Group(groupId: groupId, name: name)
        self._scenes[groupId] = [Int: Scene]()
        return groupId
    }
    
    public func renameGroup(groupId: Int, name: String) async throws {
        try await self._client.setGroupAttributes(groupId: groupId, name: name)
        
        // Update the model's cache
        self._groups[groupId]?.name = name
    }
    
    public func addLightsToGroup(groupId: Int, lightIds: [Int]) async throws {
        // Get the IDs of the lights currently in the Group, add the new light IDs to
        // that list, remove duplicates (by making them into a Set and then back to an Array),
        // and sort the list for consistency across operations.
        let lightsInGroup = self.group(withGroupId: groupId)?.lightIds ?? []
        let newLightsInGroup = Array(Set([lightsInGroup, lightIds].joined())).sorted()
        
        try await self._client.setGroupAttributes(groupId: groupId, lights: newLightsInGroup)
        
        // Update the model's cache
        let cachedGroup = self._groups[groupId]!
        cachedGroup.lightIds = newLightsInGroup
        self._groups[groupId] = cachedGroup
    }
    
    public func removeLightsFromGroup(groupId: Int, lightIds: [Int]) async throws {
        // Get the IDs of the lights currently in the Group, remove the light IDs from
        // that list and sort it for consistency across operations.
        let lightsInGroup = self.group(withGroupId: groupId)?.lightIds ?? []
        let newLightsInGroup = Array(Set(lightsInGroup).subtracting(lightIds)).sorted()
        
        try await self._client.setGroupAttributes(groupId: groupId, lights: newLightsInGroup)
        
        // Update the model's cache
        // Removing Lights from a Group also removes them from any Scenes in the
        // Group. Both cached resources need to be updated.
        let cachedGroup = self._groups[groupId]!
        cachedGroup.lightIds = newLightsInGroup
        self._groups[groupId] = cachedGroup
        
        guard let cachedGroupScenes = self._scenes[groupId] else { return }
        for (sceneId, cachedScene) in cachedGroupScenes {
            let newLightsInScene = cachedScene.lightIds.filter { newLightsInGroup.contains($0) }
            cachedScene.lightIds = newLightsInScene
            cachedScene.lightStates = cachedScene.lightStates.filter{ !lightIds.contains($0.key) }
            self._scenes[groupId]?[sceneId] = cachedScene
        }
    }
    
    public func modifyGroupState(groupId: Int, lightState: LightState) async throws {
        let restLightState = RESTLightState(alert: lightState.alert,
                                            bri: lightState.bri,
                                            ct: lightState.ct,
                                            effect: lightState.effect,
                                            on: lightState.on,
                                            xy: lightState.xy,
                                            transitiontime: lightState.transitiontime,
                                            effect_duration: lightState.effect_duration,
                                            effect_speed: lightState.effect_speed)
        
        try await self._client.setGroupState(groupId: groupId, lightState: restLightState)
        
        // Update the model's cache
        // The state of groups is currently not tracked in Group objects, though it
        // is present in RESTGroup objects and can be passed on from there if it becomes
        // needed in the future.
        // The state of the individual lights in the group can be updated.
        guard let groupLightIds = group(withGroupId: groupId)?.lightIds else { return }
        for lightId in groupLightIds {
            guard let light = light(withLightId: lightId) else { continue }
            light.state = lightState
        }
    }
    
    public func deleteGroup(groupId: Int) async throws {
        try await self._client.deleteGroup(groupId: groupId)
        
        // Uodate the model's cache
        self._groups.removeValue(forKey: groupId)
    }
    
    public var groups: [Group] {
        Array(self._groups.values)
    }
    
    public func group(withGroupId id: Int) -> Group? {
        return self._groups[id]
    }
    
    // MARK: Scenes
    
    public func createScene(groupId: Int, name: String) async throws -> Int {
        let sceneId = try await self._client.createScene(groupId: groupId, name: name)
        
        // Insert a new, empty Scene into the model's cache
        self._scenes[groupId]?[sceneId] = Scene(sceneId: sceneId, groupId: groupId, name: name)
        return sceneId
    }
    
    public func renameScene(groupId: Int, sceneId: Int, name: String) async throws {
        try await self._client.setSceneAttributes(groupId: groupId, sceneId: sceneId, name: name)
        
        // Update the model's cache
        self._scenes[groupId]?[sceneId]?.name = name
    }
    
    public func addLightsToScene(groupId: Int, sceneId: Int, lightIds: [Int]) async throws {
        // Fetch the current light state of each lightId that is passed in.
        // Modifying a scene requires also providing a light state, and the
        // light's current state will be what we use.
        var fetchedLightStates: [Int: RESTLightState] = [:]
        for lightId in lightIds {
            let lightState = try await self._client.getLightState(lightID: lightId)
            fetchedLightStates[lightId] = lightState
            try await self._client.modifyScene(groupId: groupId, sceneId: sceneId, lightIds: [lightId], lightState: lightState)
        }
        
        // Update the model's cache
        // Get the IDs of the lights currently in the Scene, add the new light IDs to
        // that list, remove duplicates (by making them into a Set and then back to an Array),
        // and sort the list for consistency across operations.
        guard let cachedScene = self._scenes[groupId]?[sceneId] else { return }
        let newLightsInScene = Array(Set([cachedScene.lightIds, lightIds].joined())).sorted()
        cachedScene.lightIds = newLightsInScene
        
        cachedScene.lightStates = lightIds.reduce(into: [Int: LightState](), { stateDictionary, lightId in
            stateDictionary[lightId] = LightState(from: fetchedLightStates[lightId]!)
        })
    }
    
    public func removeLightsFromScene(groupId: Int, sceneId: Int, lightIds: [Int]) async throws {
        // Calling 'modifyScene' with a 'nil' LightState removes the lightIds from the Scene
        for lightId in lightIds {
            try await self._client.modifyScene(groupId: groupId, sceneId: sceneId, lightIds: [lightId], lightState: nil)
        }
        
        // Update the model's cache
        guard let cachedScene = self._scenes[groupId]?[sceneId] else { return }
        let newLightsInScene = cachedScene.lightIds.filter { !lightIds.contains($0) }
        cachedScene.lightIds = newLightsInScene
        cachedScene.lightStates = cachedScene.lightStates.filter{ !lightIds.contains($0.key) }
        self._scenes[groupId]?[sceneId] = cachedScene
        
        // Removing a scene's last light causes deCONZ to also delete the scene.
        // Update the model's cache to reflect that.
        if (newLightsInScene.isEmpty) {
            self._scenes[groupId]?.removeValue(forKey: sceneId)
        }
    }
    
    public func modifyLightStateInScene(groupId: Int, sceneId: Int, lightIds: [Int], jsonLightState: String) async throws {
        let lightState = try _decoder.decode(LightState.self, from: Data(jsonLightState.utf8))
        let restLightState = RESTLightState(alert: lightState.alert,
                                            bri: lightState.bri,
                                            ct: lightState.ct,
                                            effect: lightState.effect,
                                            on: lightState.on,
                                            xy: lightState.xy,
                                            transitiontime: lightState.transitiontime,
                                            effect_duration: lightState.effect_duration,
                                            effect_speed: lightState.effect_speed)
        
        // Make use of the Hue-specific scene capabilities.
        if areHueLights(lightIds: lightIds) {
            // deCONZ's representation of a scene is very narrow, and a small subset of
            // what a Zigbee/Hue scene can be. Among other things, it is incapable of
            // representing scenes that do not contain all of the attributes deCONZ deems mandatory.
            // The Hue manufacturer-specific way of modifying scenes allows for this, but deCONZ Scenes
            // cannot represent it. A version of deCONZ that allows this flexibility in Scenes is required
            // but these changes are not part of deCONZ mainline as of 2.29.2 and thus require a custom build.
            logger.info("Modifying scene '\(sceneId, privacy: .public)' with Hue manufacturer-specific functionality")
            try await self._client.modifyHueScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds, lightState: restLightState)
        } else {
            try await self._client.modifyScene(groupId: groupId, sceneId: sceneId, lightIds: lightIds, lightState: restLightState)
        }
    }
    
    public func applyDynamicStatesToScene(groupId: Int, sceneId: Int, lightIds: [Int], jsonDynamicState: String) async throws {
        let dynamics = try _decoder.decode(DynamicState.self, from: jsonDynamicState.data(using: .utf8)!)
        
        // Map effects and colors into a single LightState array
        var lightStates: [LightState] = []
        
        for effect in dynamics.effects ?? [] {
            lightStates.append(LightState(bri: dynamics.bri,
                                          ct: dynamics.ct,
                                          effect: effect.effect,
                                          on: true,
                                          xy: effect.xy,
                                          transitiontime: dynamics.transitiontime ?? 4,
                                          effect_speed: effect.effect_speed))
        }
        
        for color in dynamics.xy ?? [] {
            lightStates.append(LightState(bri: dynamics.bri,
                                          ct: dynamics.ct,
                                          on: true,
                                          xy: color,
                                          transitiontime: dynamics.transitiontime ?? 4))
        }
        
        // !!!: deCONZ Scenes don't have 'scene_apply'
        //      Treat the missing attribute as 'sequence'
        switch dynamics.scene_apply ?? .sequence {
        case .ignore:
            // Don't update the scene attributes
            break
            
        case .sequence:
            guard !lightStates.isEmpty else { break }
            
            // Apply the colors/ct in the dynamic scene to the lights
            // in the scene in order
            for (index, lightId) in lightIds.enumerated() {
                let state = lightStates[index % lightStates.count]
                
                // Encode PresetState as JSON and get it back as a String
                let jsonData = try _encoder.encode(state)
                let jsonString = String(data: jsonData, encoding: .utf8)!
                
                try await modifyLightStateInScene(groupId: groupId, sceneId: sceneId, lightIds: [lightId], jsonLightState: jsonString)
            }
            
        case .random:
            guard !lightStates.isEmpty else { break }
            
            for lightId in lightIds {
                // Generate a random number between '0' and 'lightStates.count - 1'
                // to use as the index for the color to apply to a light.
                let random = Int(arc4random_uniform(UInt32(lightStates.count)))
                let state = lightStates[random]
                
                // Encode PresetState as JSON and get it back as a String
                let jsonData = try _encoder.encode(state)
                let jsonString = String(data: jsonData, encoding: .utf8)!
                
                try await modifyLightStateInScene(groupId: groupId, sceneId: sceneId, lightIds: [lightId], jsonLightState: jsonString)
            }
        }
        
        // Apply the Dynamic Scene
        let dynamicState = RESTDynamicState(bri: dynamics.bri,
                                            xy: dynamics.xy,
                                            ct: dynamics.ct,
                                            effect_speed: dynamics.effect_speed,
                                            auto_dynamic: dynamics.auto_dynamic)
        
        try await self._client.modifyHueDynamicScene(groupId: groupId, sceneId: sceneId, dynamicState: dynamicState)
    }
    
    public func deleteDynamicStatesFromScene(groupId: Int, sceneId: Int) async throws {
        try await self._client.modifyHueDynamicScene(groupId: groupId, sceneId: sceneId, dynamicState: nil)
    }
    
    public func deleteScene(groupId: Int, sceneId: Int) async throws {
        try await self._client.deleteScene(groupId: groupId, sceneId: sceneId)
        
        // Update the model's cache
        self._scenes[groupId]?.removeValue(forKey: sceneId)
    }
    
    public func recallScene(groupId: Int, sceneId: Int) async throws {
        try await self._client.recallScene(groupId: groupId, sceneId: sceneId)
        
        // Update the model's cache
        // The state of the individual lights in the scene can be updated to match
        // the expected state defined in the Scene.
        guard let scene = scene(withGroupId: groupId, sceneId: sceneId) else { return }
        
        let sceneLightIds = scene.lightIds
        for lightId in sceneLightIds {
            guard let light = light(withLightId: lightId),
                  let sceneLightState = scene.lightStates[lightId] else { continue }
            
            light.state = sceneLightState
        }
    }
    
    public func scenes(forGroupId id: Int) -> [Scene] {
        guard let values = self._scenes[id]?.values else { return [] }
        return Array(values)
    }
    
    public func scene(withGroupId groupId: Int, sceneId: Int) -> Scene? {
        return self._scenes[groupId]?[sceneId]
    }
    
    // MARK: Refresh
    
    public func refreshCache() async throws {
        self._lights.removeAll()
        self._groups.removeAll()
        self._scenes.removeAll()
        
        let restLights: [Int: RESTLight]
        let restGroups: [Int: RESTGroup]
        let restScenes: [Int: [Int: RESTScene]]
        
        do {
            restLights = try await _client.getAllLights()
            restGroups = try await _client.getAllGroups()
            restScenes = try await _client.getAllScenes()
        } catch {
            // Publish update
            self.onDataRefreshed.send(Date())
            
            throw error
        }
        
        // Build `Light` models
        self._lights = restLights.reduce(into: [Int: Light](), { lightDictionary, lightEntry in
            lightDictionary[lightEntry.0] = Light(from: lightEntry.1, id: lightEntry.0)
        })
        
        // Build `Scene` models with `Light`s and `LightState`s
        self._scenes = restScenes.reduce(into: [Int: [Int: Scene]](), { groupDictionary, groupEntry in
            groupDictionary[groupEntry.0] = groupEntry.1.reduce(into: [Int: Scene](), { sceneDictionary, sceneEntry in
                // Build `Light Id`s
                let sceneLightIds = sceneEntry.1.lights.compactMap { Int($0)! }
                
                // Build `LightState`s
                let sceneLightStates = sceneEntry.1.states.reduce(into: [Int: LightState](), { stateDictionary, stateEntry in
                    stateDictionary[stateEntry.0] = LightState(from: stateEntry.1)
                })
                
                sceneDictionary[sceneEntry.0] = Scene(from: sceneEntry.1, sceneId: sceneEntry.0, groupId: groupEntry.0, lightIds: sceneLightIds, lightStates: sceneLightStates, dynamicState: DynamicState(from: sceneEntry.1.dynamics))
            })
        })
        
        // Build `Group` models with `Light`s and `Scene`s
        self._groups = restGroups.reduce(into: [Int: Group](), { groupDictionary, groupEntry in
            // Build `Light Id`s
            let groupLightIds = groupEntry.1.lights.compactMap { Int($0)! }
            
            // Build `Scene Id`s
            let groupSceneIds = groupEntry.1.scenes.compactMap { Int($0)! }
            
            groupDictionary[groupEntry.0] = Group(from: groupEntry.1, id: groupEntry.0, lightIds: groupLightIds, sceneIds: groupSceneIds)
        })
        
        // Publish update
        self.onDataRefreshed.send(Date())
    }
}
