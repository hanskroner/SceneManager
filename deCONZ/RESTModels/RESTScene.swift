//
//  RESTScene.swift
//  deCONZ
//
//  Created by Hans Kröner on 27/10/2024.
//

import OSLog

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "rest-scene")

// MARK: Scene Group

struct RESTSceneGroup: Codable {
    let id: String
    let scenes: [Int: RESTScene]
}

// MARK: Scene

struct RESTScene: Codable {
    let id: String
    let lights: [String]
    let name: String
    let states: [Int: RESTLightState]
    let dynamics: RESTDynamicState?
}

extension Scene {
    convenience init (from scene: RESTScene, sceneId: Int, groupId: Int, lightIds: [Int], lightStates: [Int: LightState], dynamicState: DynamicState?) {
        self.init(sceneId: sceneId, groupId: groupId, name: scene.name, lightIds: lightIds, lightStates: lightStates, dynamicState: dynamicState)
    }
}

struct RESTSceneAttributes: Codable {
    var dynamics: RESTDynamicState?
    var lights: [Int: RESTLightState]
    var name: String
}

// MARK: - Dynamic Scene State

struct RESTDynamicState: Codable {
    let bri: Int?
    let xy: [[Double]]?
    let ct: Int?
    
    let effect_speed: Double
    let auto_dynamic: Bool
}

extension DynamicState {
    convenience init?(from dynamicState: RESTDynamicState?) {
        guard let dynamicState else { return nil }
        
        self.init(bri: dynamicState.bri, xy: dynamicState.xy, ct: dynamicState.ct, effect_speed: dynamicState.effect_speed, auto_dynamic: dynamicState.auto_dynamic, scene_apply: DynamicStateApplication.ignore)
    }
}
