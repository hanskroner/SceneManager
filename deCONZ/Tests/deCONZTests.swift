//
//  deCONZTests.swift
//  deCONZTests
//
//  Created by Hans Kröner on 26/10/2024.
//

import Testing
import OSLog

@testable import deCONZ

private let apiKey = ProcessInfo.processInfo.environment["DECONZ_API_KEY"] ?? ""
private let apiURL = ProcessInfo.processInfo.environment["DECONZ_API_URL"] ?? ""

private let decoder = JSONDecoder()
private let encoder = JSONEncoder()

struct deCONZTests {
    
    private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "tests")
    private let client = deCONZ.RESTClient(apiKey: apiKey, apiURL: apiURL)

    @Test func testAllLights() async throws {
        let lights = try await client.getAllLights()
        for (lightId, light) in lights {
            logger.info("\(lightId, privacy: .public) - \(light.name, privacy: .public)")
        }
    }
    
    @Test func testAllGroups() async throws {
        let groups = try await client.getAllGroups()
        for (groupId, group) in groups {
            logger.info("\(groupId, privacy: .public) - \(group.name, privacy: .public) - \(group.scenes, privacy: .public)")
        }
    }
        
    @Test func testAllScenes() async throws {
        let scenes = try await client.getAllScenes()
        for (groupId, group) in scenes {
            for (sceneId, scene) in group {
                logger.info("\(groupId, privacy: .public), \(sceneId, privacy: .public) - \(scene.name, privacy: .public) - \(scene.lights, privacy: .public)")
            }
        }
    }
    
    @Test func testBuildModels() async throws {
        // Build `Light` models
        let restLights = try await client.getAllLights()
        let lights = restLights.reduce(into: [Int: Light](), { lightDictionary, lightEntry in
            lightDictionary[lightEntry.0] = Light(from: lightEntry.1, id: lightEntry.0)
        })
        
        for (lightId, light) in lights {
            logger.info("\(lightId, privacy: .public) - \(light.name, privacy: .public) - \(light.state.description, privacy: .public)")
        }
        
        // Build `Scene` models with `Light`s and `LightState`s
        let restScenes = try await client.getAllScenes()
        let scenes = restScenes.reduce(into: [Int: [Int: Scene]](), { groupDictionary, groupEntry in
            groupDictionary[groupEntry.0] = groupEntry.1.reduce(into: [Int: Scene](), { sceneDictionary, sceneEntry in
                // Build `Light`s
                let sceneLightIds = sceneEntry.1.lights.compactMap { lights[Int($0)!]?.lightId }
                
                // Build `LightState`s
                let sceneLightStates = sceneEntry.1.states.reduce(into: [Int: LightState](), { stateDictionary, stateEntry in
                    stateDictionary[stateEntry.0] = LightState(from: stateEntry.1)
                })
                
                sceneDictionary[sceneEntry.0] = Scene(from: sceneEntry.1, sceneId: sceneEntry.0, groupId: groupEntry.0, lightIds: sceneLightIds, lightStates: sceneLightStates, dynamicState: DynamicState(from: sceneEntry.1.dynamics))
            })
        })
        
        for (groupId, group) in scenes {
            for (sceneId, scene) in group {
                logger.info("\(groupId, privacy: .public), \(sceneId, privacy: .public) - \(scene.name, privacy: .public) - \(scene.lightIds.map { lights[$0]!.name }, privacy: .public) - \(scene.lightStates.mapValues { $0.description }, privacy: .public)")
            }
        }
        
        // Build `Group` models with `Light`s and `Scene`s
        let restGroups = try await client.getAllGroups()
        let groups = restGroups.reduce(into: [Int: Group](), { groupDictionary, groupEntry in
            // Build `LightId`s
            let groupLightIds = groupEntry.1.lights.compactMap { lights[Int($0)!]?.lightId }
            
            // Build `SceneIds`s
            let groupSceneIds = groupEntry.1.scenes.compactMap { scenes[groupEntry.0]?[Int($0)!]?.sceneId }
            
            groupDictionary[groupEntry.0] = Group(from: groupEntry.1, id: groupEntry.0, lightIds: groupLightIds, sceneIds: groupSceneIds)
        })
        
        for (groupId, group) in groups {
            logger.info("\(groupId, privacy: .public) - \(group.name, privacy: .public) - \(group.lightIds.map { lights[$0]!.name }, privacy: .public) - \(group.sceneIds.map { scenes[groupId]![$0]!.name }, privacy: .public)")
        }
    }
    
    @Test func testLightState() async throws {
        let lightState = try await client.getLightState(lightID: 5)
        
        let encoded = try encoder.encode(lightState)
        let decoded = try decoder.decode(JSON.self, from: encoded)
        
        logger.info("\(decoded.prettyPrint(), privacy: .public)")
    }
}
