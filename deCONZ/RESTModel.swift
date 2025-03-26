//
//  RESTModel.swift
//  SceneManager
//
//  Created by Hans Kröner on 10/11/2024.
//

import Combine
import OSLog

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "rest-model")

@Observable
public final class RESTModel {
    private var _lights: [Int: Light] = [:]
    private var _groups: [Int: Group] = [:]
    private var _scenes: [Int: [Int: Scene]] = [:]
    
    // Combine Publishers
    public let onDataRefreshed = PassthroughSubject<Date, Never>()
    
    private let _client: RESTClient
    
    private let _decoder = JSONDecoder()
    private let _encoder = JSONEncoder()
    
    private static let apiKey = UserDefaults.standard.string(forKey: "deconz_key") ?? ""
    private static let apiURL = UserDefaults.standard.string(forKey: "deconz_url") ?? ""
    public static let shared = RESTModel(client: RESTClient.init(apiKey: apiKey, apiURL: apiURL))
    
    private init(client: RESTClient) {
        _client = client
        
        Task {
            do {
                try await refreshCache()
            } catch {
                logger.error("\(error, privacy: .public)")
            }
        }
    }
    
    // MARK: Lights
    
    public var lights: [Light] {
        Array(self._lights.values)
    }
    
    public func light(withLightId id: Int) -> Light? {
        return self._lights[id]
    }
    
    // MARK: Light State
    
    // FIXME: Consider different return from 'String'
    public func lightState(withLightId lightId: Int, groupId: Int? = nil, sceneId: Int? = nil) async -> String {
        // Current state of the light
        guard let groupId, let sceneId else {
            // FIXME: Catch
            let state = try! await self._client.getLightState(lightID: lightId)
            let encoded = try! _encoder.encode(state)
            let decoded = try! _decoder.decode(JSON.self, from: encoded)
            
            return decoded.prettyPrint()
        }
        
        // State defined in a scene
        // FIXME: Catch
        let state = try! await self._client.getSceneState(lightId: lightId, groupID: groupId, sceneID: sceneId)
        let encoded = try! _encoder.encode(state)
        let decoded = try! _decoder.decode(JSON.self, from: encoded)
        
        return decoded.prettyPrint()
    }
    
    // MARK: Groups
    
    public func createGroup(name: String) async -> Int? {
        do {
            let groupId = try await self._client.createGroup(name: name)
            
            // Insert a new, empty Group into the model's cache
            self._groups[groupId] = Group(groupId: groupId, name: name)
            self._scenes[groupId] = [Int: Scene]()
            return groupId
        } catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }
    
    public func renameGroup(groupId: Int, name: String) async {
        do {
            try await self._client.setGroupAttributes(groupId: groupId, name: name)
            
            // Update the model's cache
            self._groups[groupId]?.name = name
        } catch {
            logger.error("\(error, privacy: .public)")
        }
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
    
    public func deleteGroup(groupId: Int) async {
        do {
            try await self._client.deleteGroup(groupId: groupId)
            
            // Uodate the model's cache
            self._groups.removeValue(forKey: groupId)
        } catch {
            logger.error("\(error, privacy: .public)")
        }
    }
    
    public var groups: [Group] {
        Array(self._groups.values)
    }
    
    public func group(withGroupId id: Int) -> Group? {
        return self._groups[id]
    }
    
    // MARK: Scenes
    
    public func createScene(groupId: Int, name: String) async -> Int? {
        do {
            let sceneId = try await self._client.createScene(groupId: groupId, name: name)
            
            // Insert a new, empty Scene into the model's cache
            self._scenes[groupId]?[sceneId] = Scene(sceneId: sceneId, groupId: groupId, name: name)
            return sceneId
        } catch {
            logger.error("\(error, privacy: .public)")
            return nil
        }
    }
    
    public func renameScene(groupId: Int, sceneId: Int, name: String) async {
        do {
            try await self._client.setSceneAttributes(groupId: groupId, sceneId: sceneId, name: name)
            
            // Update the model's cache
            self._scenes[groupId]?[sceneId]?.name = name
        } catch {
            logger.error("\(error, privacy: .public)")
        }
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
        // FIXME: Bug when removing last light
        //        Removing a scene's last light causes deCONZ to also
        //        delete the scene. That needs to be taken into account here.
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
    }
    
    public func modifyLightStateInScene(groupId: Int, sceneId: Int, lightIds: [Int], jsonLightState: String) async throws {
        let lightState = try _decoder.decode(LightState.self, from: Data(jsonLightState.utf8))
        try await self._client.modifyScene(groupId: groupId,
                                           sceneId: sceneId,
                                           lightIds: lightIds,
                                           lightState: RESTLightState(alert: lightState.alert,
                                                                      bri: lightState.bri,
                                                                      colormode: nil,
                                                                      ct: lightState.ct,
                                                                      effect: lightState.effect,
                                                                      hue: nil,
                                                                      on: lightState.on,
                                                                      reachable: nil,
                                                                      sat: nil,
                                                                      xy: lightState.xy,
                                                                      transitiontime: lightState.transitiontime,
                                                                      effect_duration: lightState.effect_duration,
                                                                      effect_speed: lightState.effect_speed))
    }
    
    public func deleteScene(groupId: Int, sceneId: Int) async {
        do {
            try await self._client.deleteScene(groupId: groupId, sceneId: sceneId)
            
            // Update the model's cache
            self._scenes[groupId]?.removeValue(forKey: sceneId)
        } catch {
            logger.error("\(error, privacy: .public)")
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
        let restLights = try await _client.getAllLights()
        let restGroups = try await _client.getAllGroups()
        let restScenes = try await _client.getAllScenes()
        
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
                
                sceneDictionary[sceneEntry.0] = Scene(from: sceneEntry.1, sceneId: sceneEntry.0, groupId: groupEntry.0, lightIds: sceneLightIds, lightStates: sceneLightStates)
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
