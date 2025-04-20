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
    let bri: RESTLightConfigurationBri?
    let color: RESTLightConfigurationColor?
    let groups: [String]?
    let on: RESTLightConfigurationOn?
}

enum RESTLightConfigurationBriStartup: Codable {
    case int(Int)
    case string(String)
}

struct RESTLightConfigurationBri: Codable {
    enum CodingKeys: String, CodingKey {
        case couple_ct, execute_if_off, startup
    }
    
    let couple_ct: Bool?
    let execute_if_off: Bool?
    let startup: RESTLightConfigurationBriStartup?
    
    init(couple_ct: Bool? = nil, execute_if_off: Bool? = nil, startup: RESTLightConfigurationBriStartup? = nil) {
        self.couple_ct = couple_ct
        self.execute_if_off = execute_if_off
        self.startup = startup
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.couple_ct = try container.decodeIfPresent(Bool.self, forKey: .couple_ct)
        self.execute_if_off = try container.decodeIfPresent(Bool.self, forKey: .execute_if_off)
        
        if let value = try? container.decode(Int.self, forKey: .startup) {
            self.startup = .int(value)
        } else if let value = try? container.decode(String.self, forKey: .startup) {
            self.startup = .string(value)
        } else {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value for 'startup'")
            throw DecodingError.typeMismatch(RESTLightConfigurationBriStartup.self, context)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(couple_ct, forKey: .couple_ct)
        try container.encodeIfPresent(execute_if_off, forKey: .execute_if_off)
        
        switch startup {
        case .int(let value):
            try container.encode(value, forKey: .startup)
        case .string(let string):
            try container.encode(string, forKey: .startup)
        case .none:
            break
        }
    }
}

struct RESTLightConfigurationColor: Codable {
    let ct: RESTLightConfigurationColorCt?
    let execute_if_off: Bool?
    let xy: RESTLightConfigurationColorXy?
    
    init(ct: RESTLightConfigurationColorCt? = nil, execute_if_off: Bool? = nil, xy: RESTLightConfigurationColorXy? = nil) {
        self.ct = ct
        self.execute_if_off = execute_if_off
        self.xy = xy
    }
}

enum RESTLightConfigurationColorCtStartup: Codable {
    case int(Int)
    case string(String)
}

struct RESTLightConfigurationColorCt: Codable {
    enum CodingKeys: String, CodingKey {
        case startup
    }
    
    let startup: RESTLightConfigurationColorCtStartup?
    
    init(startup: RESTLightConfigurationColorCtStartup? = nil) {
        self.startup = startup
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let value = try? container.decode(Int.self, forKey: .startup) {
            self.startup = .int(value)
        } else if let value = try? container.decode(String.self, forKey: .startup) {
            self.startup = .string(value)
        } else {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value for 'startup'")
            throw DecodingError.typeMismatch(RESTLightConfigurationColorCtStartup.self, context)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch startup {
        case .int(let value):
            try container.encode(value, forKey: .startup)
        case .string(let string):
            try container.encode(string, forKey: .startup)
        case .none:
            break
        }
    }
}

enum RESTLightConfigurationColorXyStartup: Codable {
    case double([Double])
    case string(String)
}

struct RESTLightConfigurationColorXy: Codable {
    enum CodingKeys: String, CodingKey {
        case startup
    }
    
    let startup: RESTLightConfigurationColorXyStartup?
    
    init(startup: RESTLightConfigurationColorXyStartup? = nil) {
        self.startup = startup
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let value = try? container.decode([Double].self, forKey: .startup) {
            self.startup = .double(value)
        } else if let value = try? container.decode(String.self, forKey: .startup) {
            self.startup = .string(value)
        } else {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value for 'startup'")
            throw DecodingError.typeMismatch(RESTLightConfigurationColorXyStartup.self, context)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch startup {
        case .double(let value):
            try container.encode(value, forKey: .startup)
        case .string(let string):
            try container.encode(string, forKey: .startup)
        case .none:
            break
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
    
    init(startup: RESTLightConfigurationOnStartup? = nil) {
        self.startup = startup
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let value = try? container.decode(Bool.self, forKey: .startup) {
            self.startup = .bool(value)
        } else if let value = try? container.decode(String.self, forKey: .startup) {
            self.startup = .string(value)
        } else {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value for 'startup'")
            throw DecodingError.typeMismatch(RESTLightConfigurationOnStartup.self, context)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch startup {
        case .bool(let value):
            try container.encode(value, forKey: .startup)
        case .string(let string):
            try container.encode(string, forKey: .startup)
        case .none:
            break
        }
    }
}

// MARK: - Extension

extension RESTLightConfiguration {
    init(configuration: LightConfiguration) {
        let startupOn: RESTLightConfigurationOnStartup = {
            switch configuration.on.startupOn {
            case .previous: return .string("previous")
            case .value(let on): return .bool(on)
            }
        }()
        
        let startupBri: RESTLightConfigurationBriStartup = {
            switch configuration.bri.startupBri {
            case .previous: return .string("previous")
            case .value(let bri): return .int(bri)
            }
        }()
        
        let startupCt = {
            switch configuration.color.startupCt {
            case .previous: return RESTLightConfigurationColorCt(startup: .string("previous"))
            case .value(let ct): return RESTLightConfigurationColorCt(startup: .int(ct))
            }
        }()
        
        let startupXy = {
            switch configuration.color.startupXy {
            case .previous: return RESTLightConfigurationColorXy(startup: .string("previous"))
            case .value(let xy): return RESTLightConfigurationColorXy(startup: .double(xy))
            }
        }()
        
        self.bri = RESTLightConfigurationBri(couple_ct: configuration.bri.coupleCt,
                                                    execute_if_off: configuration.bri.executeIfOff,
                                                    startup: startupBri)
        
        self.color = RESTLightConfigurationColor(ct: startupCt,
                                                execute_if_off: configuration.color.executeIfOff,
                                                xy: startupXy)
        self.groups = nil
        
        self.on = RESTLightConfigurationOn(startup: startupOn)
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

extension LightConfiguration {
    init (from light: RESTLight, id lightId: Int) {
        // 'on' configuration
        let startupOn: LightConfigurationOnStartup
        switch light.config?.on?.startup {
        case .bool(let value):
            startupOn = .value(on: value)
            
        case .string(_):
            // !!!: Any string is assumed to be 'previous'
            startupOn = .previous
            
        default:
            // !!!: A missing entry is assumed to be 'previous'
            startupOn = .previous
        }
        
        let configurationOn = LightConfigurationOn(startupOn: startupOn)
        
        // 'bri' configuration
        let startupBri: LightConfigurationBriStartup
        switch light.config?.bri?.startup {
        case .int(let value):
            startupBri = .value(bri: value)
            
        case .string(_):
            // !!!: Any string is assumed to be 'previous'
            startupBri = .previous
            
        default:
            // !!!: A missing entry is assumed to be 'previous'
            startupBri = .previous
        }
        
        let executeIfOffBri: Bool = light.config?.bri?.execute_if_off ?? false
        let coupleCt: Bool = light.config?.bri?.couple_ct ?? false
        let configurationBri = LightConfigurationBri(startupBri: startupBri, executeIfOff: executeIfOffBri, coupleCt: coupleCt)
        
        // 'color' configuration
        let startupCt: LightConfigurationCtStartup
        switch light.config?.color?.ct?.startup {
        case .int(let value):
            startupCt = .value(ct: value)
            
        case .string(_):
            // !!!: Any string is assumed to be 'previous'
            startupCt = .previous
            
        default:
            // !!!: A missing entry is assumed to be 'previous'
            startupCt = .previous
        }
        
        let startupXy: LightConfigurationXyStartup
        switch light.config?.color?.xy?.startup {
        case .double(let xy):
            startupXy = .value(xy: [xy[0], xy[1]])
            
        case .string(_):
            // !!!: Any string is assumed to be 'previous'
            startupXy = .previous
            
        default:
            // !!!: A missing entry is assumed to be 'previous'
            startupXy = .previous
        }
        
        let executeIfOffXy: Bool = light.config?.color?.execute_if_off ?? false
        let configurationColor = LightConfigurationColor(startupCt: startupCt, startupXy: startupXy, executeIfOff: executeIfOffXy)
        
        self.init(lightId: lightId,
                  name: light.name,
                  modelId: light.modelid,
                  on: configurationOn,
                  bri: configurationBri,
                  color: configurationColor)
    }
}
