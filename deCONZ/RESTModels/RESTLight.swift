//
//  RESTLight.swift
//  deCONZ
//
//  Created by Hans Kröner on 27/10/2024.
//

import OSLog

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "rest-light")

// MARK: Light

struct RESTLight: Codable {
    let config: RESTLightConfiguration?
    let manufacturername: String
    let modelid: String
    let name: String
    let swversion: String?
    let state: RESTLightState
    let type: String
    let uniqueid: String
    
    // TODO: Add 'capabilities'
    
    // Hue-specific
     let productid: String?
     let productname: String?
}

// MARK: Light State

struct RESTLightState: Codable {
    let alert: String?
    let bri: Int?
    let colormode: String?
    let ct: Int?
    let effect: String?
    let hue: Int?
    let on: Bool?
    let reachable: Bool?
    let sat: Int?
    let xy: [Double]?
    
    let transitiontime: Int?
    let effect_duration: Int?
    let effect_speed: Double?
    
    init(alert: String? = nil,
         bri: Int? = nil,
         colormode: String? = nil,
         ct: Int? = nil,
         effect: String? = nil,
         hue: Int? = nil,
         on: Bool? = nil,
         reachable: Bool? = nil,
         sat: Int? = nil,
         xy: [Double]? = nil,
         transitiontime: Int? = nil,
         effect_duration: Int? = nil,
         effect_speed: Double? = nil) {
        self.alert = alert
        self.bri = bri
        self.colormode = colormode
        self.ct = ct
        self.effect = effect
        self.hue = hue
        self.on = on
        self.reachable = reachable
        self.sat = sat
        self.xy = xy
        self.transitiontime = transitiontime
        self.effect_duration = effect_duration
        self.effect_speed = effect_speed
    }
}

// MARK: Light Configuration

struct RESTLightConfiguration: Codable {
    let bri: RESTLightConfigurationBrightness?
    let color: RESTLightConfigurationColor?
    let groups: [String]?
    let on: RESTLightConfigurationOn?
}

enum RESTLightConfigurationBrightnessStartup: Codable {
    case int(Int)
    case string(String)
}

struct RESTLightConfigurationBrightness: Codable {
    enum CodingKeys: String, CodingKey {
        case couple_ct, execute_if_off, startup
    }
    
    let couple_ct: Bool?
    let execute_if_off: Bool?
    let startup: RESTLightConfigurationBrightnessStartup?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.couple_ct = try container.decodeIfPresent(Bool.self, forKey: .couple_ct)
        self.execute_if_off = try container.decodeIfPresent(Bool.self, forKey: .execute_if_off)
        
        if let value = try? container.decode(Int.self, forKey: .startup) {
            // FIXME: Temp. info to normalize 'startup' of my house lights
            logger.info("Path \(decoder.codingPath) contains non-'previous' startup")
            self.startup = .int(value)
        } else if let value = try? container.decode(String.self, forKey: .startup) {
            self.startup = .string(value)
        } else {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value for 'startup'")
            throw DecodingError.typeMismatch(RESTLightConfigurationBrightnessStartup.self, context)
        }
    }
}

struct RESTLightConfigurationColor: Codable {
    let ct: RESTLightConfigurationColorCT?
    let execute_if_off: Bool?
    let xy: RESTLightConfigurationColorXY?
}

enum RESTLightConfigurationColorCTStartup: Codable {
    case int(Int)
    case string(String)
}

struct RESTLightConfigurationColorCT: Codable {
    enum CodingKeys: String, CodingKey {
        case startup
    }
    
    let startup: RESTLightConfigurationColorCTStartup?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let value = try? container.decode(Int.self, forKey: .startup) {
            // FIXME: Temp. info to normalize 'startup' of my house lights
            logger.info("Path \(decoder.codingPath) contains non-'previous' startup")
            self.startup = .int(value)
        } else if let value = try? container.decode(String.self, forKey: .startup) {
            self.startup = .string(value)
        } else {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value for 'startup'")
            throw DecodingError.typeMismatch(RESTLightConfigurationColorCTStartup.self, context)
        }
    }
}

enum RESTLightConfigurationColorXYStartup: Codable {
    case double([Double])
    case string(String)
}

struct RESTLightConfigurationColorXY: Codable {
    enum CodingKeys: String, CodingKey {
        case startup
    }
    
    let startup: RESTLightConfigurationColorXYStartup?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let value = try? container.decode([Double].self, forKey: .startup) {
            // FIXME: Temp. info to normalize 'startup' of my house lights
            logger.info("Path \(decoder.codingPath) contains non-'previous' startup")
            self.startup = .double(value)
        } else if let value = try? container.decode(String.self, forKey: .startup) {
            self.startup = .string(value)
        } else {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value for 'startup'")
            throw DecodingError.typeMismatch(RESTLightConfigurationColorXYStartup.self, context)
        }
    }
}

enum RESTLightConfigurationOnStartup: Codable {
    case bool(Bool)
    case string(String)
}

struct RESTLightConfigurationOn: Codable {
    enum CodingKeys: String, CodingKey {
        case startup
    }
    
    let startup: RESTLightConfigurationOnStartup?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let value = try? container.decode(Bool.self, forKey: .startup) {
            // FIXME: Temp. info to normalize 'startup' of my house lights
            logger.info("Path \(decoder.codingPath) contains non-'previous' startup")
            self.startup = .bool(value)
        } else if let value = try? container.decode(String.self, forKey: .startup) {
            self.startup = .string(value)
        } else {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value for 'startup'")
            throw DecodingError.typeMismatch(RESTLightConfigurationOnStartup.self, context)
        }
    }
}

extension LightState {
    convenience init (from state: RESTLightState) {
        self.init()
        
        self.alert = state.alert
        self.bri = state.bri
        self.ct = state.ct
        self.effect = state.effect
        self.on = state.on
        self.xy = state.xy
    }
}

extension Light {
    convenience init (from light: RESTLight, id lightId: Int) {
        self.init(lightId: lightId,
                  name: light.name,
                  state: LightState(from: light.state),
                  manufacturer: light.manufacturername,
                  modelId: light.modelid)
    }
}
