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
}

extension Scene {
    convenience init (from scene: RESTScene, sceneId: Int, groupId: Int, lightIds: [Int], lightStates: [Int: LightState]) {
        self.init(sceneId: sceneId, groupId: groupId, name: scene.name, lightIds: lightIds, lightStates: lightStates)
    }
}
