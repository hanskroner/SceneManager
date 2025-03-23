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
    
    public var groups: [Group] {
        Array(self._groups.values)
    }
    
    public func group(withGroupId id: Int) -> Group? {
        return self._groups[id]
    }
    
    // MARK: Scenes
    
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
