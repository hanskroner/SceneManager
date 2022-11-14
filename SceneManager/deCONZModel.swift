//
//  deCONZModel.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import Foundation

// MARK: - deCONZ REST API Containers

struct deCONZLight: Codable, Hashable {
    var id: String?
    var name: String?
    var manufacturer: String?
    var modelid: String?
    var type: String?
    var state: deCONZLightState?
}

struct deCONZScene: Codable {
    var id: String?
    var name: String?
    var lights: [String]?
}

struct deCONZGroup: Codable {
    var id: String?
    var name: String?
    var lights: [String]?
    var scenes: [String]?
    var devicemembership: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case lights
        case devicemembership
    }
}

struct deCONZLightState: Hashable, Codable {
    var id: String?
    var on: Bool?
    var bri: Int?
    var transitiontime: Int?
    var colormode: String?
    var ct: Int?
    var x: Double?
    var y: Double?
    var xy: [Double]?
    
    var prettyPrint: String {
        var buffer = "{\n"
        buffer += "  \"bri\" : \(bri ?? 0),\n"
        buffer += "  \"colormode\" : \"\(colormode ?? "")\",\n"
        if let ct = ct {
            buffer += "  \"ct\" : \(ct),\n"
        }
        buffer += "  \"on\" : \(on ?? false),\n"
        buffer += "  \"transitiontime\" : \(transitiontime ?? 0)"
        if let x = x, let y = y {
            buffer += ",\n"
            buffer += String(format: "  \"x\" : %06.4f,\n", x)
            buffer += String(format: "  \"y\" : %06.4f", y)
        }
        buffer += "\n}"
        
        return buffer
    }
}

// MARK: - deCONZ REST API Error Handling

enum deCONZError: Error {
    case apiError(context: deCONZErrorContext)
    case unknownResponse(data: Data?, response: URLResponse?)
}

extension deCONZError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .apiError(let context):
            return context.description
        case .unknownResponse(data: _, response: _):
            return "Unknown HTTP response from deCONZ REST API host"
        }
    }
}

struct deCONZErrorContext: Decodable {
    let type: Int
    let address: String
    let description: String
    
    enum CodingKeys: String, CodingKey {
        case error
    }
    
    enum ErrorKeys: String, CodingKey {
        case type
        case address
        case description
    }
    
    init(from decoder: Decoder) throws {
        let rootContainer = try decoder.container(keyedBy: CodingKeys.self)
        let errorContainer = try rootContainer.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error)
        type = try errorContainer.decode(Int.self, forKey: .type)
        address = try errorContainer.decode(String.self, forKey: .address)
        description = try errorContainer.decode(String.self, forKey: .description)
    }
}

struct deCONZSuccessContext: Decodable {
    let id: String
    
    enum CodingKeys: String, CodingKey {
        case success
    }
    
    enum SuccessKeys: String, CodingKey {
        case id
    }
    
    init(from decoder: Decoder) throws {
        let rootContainer = try decoder.container(keyedBy: CodingKeys.self)
        let successContainer = try rootContainer.nestedContainer(keyedBy: SuccessKeys.self, forKey: .success)
        id = try successContainer.decode(String.self, forKey: .id)
    }
}
