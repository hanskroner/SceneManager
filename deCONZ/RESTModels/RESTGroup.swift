//
//  RESTGroup.swift
//  deCONZ
//
//  Created by Hans Kröner on 27/10/2024.
//

import OSLog

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "rest-group")

// MARK: Group Scene

struct RESTGroupScene: Codable {
    let id: String
}

// MARK: Group

struct RESTGroup: Codable {
    enum CodingKeys: String, CodingKey {
        case lights, name, scenes, state, type, devicemembership
    }
    
    let lights: [String]
    let name: String
    let scenes: [String]
    let state: RESTGroupState
    let type: String
    let devicemembership: [String]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.lights = try container.decode([String].self, forKey: .lights)
        
        let groupScenes = try container.decode([RESTGroupScene].self, forKey: .scenes)
        self.scenes = groupScenes.map { $0.id }
        
        self.name = try container.decode(String.self, forKey: .name)
        self.state = try container.decode(RESTGroupState.self, forKey: .state)
        self.type = try container.decode(String.self, forKey: .type)
        self.devicemembership = try container.decode([String].self, forKey: .devicemembership)
    }
}

// MARK: Group State

struct RESTGroupState: Codable {
    let all_on: Bool
    let any_on: Bool
}

extension Group {
    convenience init (from group: RESTGroup, id groupId: Int, lightIds: [Int], sceneIds: [Int]) {
        self.init(groupId: groupId, name: group.name, lightIds: lightIds, sceneIds: sceneIds)
    }
}
