//
//  RESTObjects.swift
//  deCONZ
//
//  Created by Hans Kröner on 24/03/2025.
//

// MARK: Light

struct RESTLightObject: Codable, Hashable {
    var id: String?
    var name: String?
}

// MARK: Group

struct RESTGroupObject: Codable, Hashable {
    var id: String?
    var name: String?
    var lights: [String]?
    var scenes: [RESTSceneObject]?
    var devicemembership: [String]?
}

// MARK: Scene

struct RESTSceneObject: Codable, Hashable {
    var id: String?
    var name: String?
    var transitiontime: Int?
    var lightcount: Int?
}
