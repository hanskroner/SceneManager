//
//  deCONZModel.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import Foundation

// MARK: - Models

enum deCONZLightColorMode: Hashable {
    case ct(Int)
    case xy(Double, Double)
}

struct deCONZLightState: Hashable {
    var on: Bool
    var bri: Int
    var transitiontime: Int?
    var colormode: deCONZLightColorMode
    
    var prettyPrint: String {
        var buffer = "{\n"
        buffer += "  \"bri\" : \(bri),\n"
        
        // !!!: 'hs' mode (Hue/Saturation) is not supported
        switch self.colormode {
        case .ct(let ct):
            buffer += "  \"colormode\" : \"ct\",\n"
            buffer += "  \"ct\" : \(ct),\n"
        
        default:
            buffer += "  \"colormode\" : \"xy\",\n"
        }
        
        buffer += "  \"on\" : \(on),\n"
        buffer += "  \"transitiontime\" : \(transitiontime ?? 0)"
        
        switch self.colormode {
        case .xy(let x, let y):
            buffer += ",\n"
            buffer += String(format: "  \"xy\" : [%06.4f, %06.4f]", x, y)
        
        default: break
        }
        
        buffer += "\n}"

        return buffer
    }
}

extension deCONZLightState: Codable {
    enum CodingKeys: CodingKey {
        case on, bri, transitiontime, colormode, ct, xy, x, y
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        on = try container.decode(Bool.self, forKey: .on)
        bri = try container.decode(Int.self, forKey: .bri)
        transitiontime = try? container.decode(Int?.self, forKey: .transitiontime)
        
        let _colormode = try container.decode(String?.self, forKey: .colormode)
        let ct = try? container.decode(Int?.self, forKey: .ct)
        let xy = try? container.decode([Double]?.self, forKey: .xy)
        let x = try? container.decode(Double?.self, forKey: .x)
        let y = try? container.decode(Double?.self, forKey: .y)
        
        if (_colormode == "ct") && ct != nil {
            colormode = deCONZLightColorMode.ct(ct!)
        } else if (_colormode == "xy") && xy != nil {
            colormode = deCONZLightColorMode.xy(xy![0], xy![1])
        } else if (_colormode == "xy") && x != nil && y != nil {
            colormode = deCONZLightColorMode.xy(x!, y!)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unable to decode light state"
                )
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(on, forKey: .on)
        try container.encode(bri, forKey: .bri)
        if let transitiontime = self.transitiontime {
            try container.encode(transitiontime, forKey: .transitiontime)
        }
        
        switch self.colormode {
        case .ct(let ct):
            try container.encode("ct", forKey: .colormode)
            try container.encode(ct, forKey: .ct)
        case .xy(let x, let y):
            try container.encode("xy", forKey: .colormode)
            try container.encode([x, y], forKey: .xy)
        }
    }
}

struct deCONZLight: Codable, Hashable {
    var id: Int
    var name: String
    var manufacturer: String
    var modelid: String
    var type: String
}

struct deCONZScene: Codable, Hashable {
    var id: Int
    var gid: Int
    var name: String
}

struct deCONZGroup: Codable, Hashable {
    var id: Int
    var name: String
    var lights: [Int]
    var scenes: [Int]
}

// MARK: - REST API Returns

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
