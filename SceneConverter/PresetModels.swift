//
//  PresetModels.swift
//  SceneConverter
//
//  Created by Hans Kröner on 03/04/2025.
//

import Foundation

enum PresetError: LocalizedError {
    case notAPreset
    case notAPresetState
    case notAPresetDynamics
    
    var errorDescription: String? {
        switch self {
        case .notAPreset:
            return "Not a Preset"
        case .notAPresetState:
            return "Not a PresetState"
        case .notAPresetDynamics:
            return "Not a PresetDynamics"
        }
    }
}

struct Preset: Codable {
    let name: String
    let state: PresetStateDefinition
    
    enum CodingKeys: CodingKey {
        case name, state, dynamics
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        
        let recall = try? container.decodeIfPresent(PresetState.self, forKey: .state)
        let dynamic = try? container.decodeIfPresent(PresetDynamics.self, forKey: .dynamics)
        
        if let recall = recall {
            self.state = .recall(recall)
        } else if let dynamic = dynamic {
            self.state = .dynamic(dynamic)
        } else {
            throw PresetError.notAPreset
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(name, forKey: .name)
        
        switch state {
        case .recall(let recall):
            try container.encode(recall, forKey: .state)
        case .dynamic(let dynamic):
            try container.encode(dynamic, forKey: .dynamics)
        }
    }
    
}

extension Preset {
    init(from scene: CLIPScene) throws {
        self.name = scene.metadata.name
        
        if let recallState = try? PresetState(from: scene) {
            // 'Recall' state
            self.state = .recall(recallState)
        } else if let dynamicState = try? PresetDynamics(from: scene) {
            // 'Dynamic' state
            self.state = .dynamic(dynamicState)
        } else {
            throw PresetError.notAPreset
        }
    }
}

// MARK: - Models

enum PresetStateDefinition: Codable {
    case recall(PresetState)
    case dynamic(PresetDynamics)
    
    enum CodingKeys: CodingKey {
        case recall, dynamic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .recall(let recall):
            try container.encode(recall, forKey: .recall)
        case .dynamic(let dynamic):
            try container.encode(dynamic, forKey: .dynamic)
        }
    }
}

enum PresetDynamicsApplication: String, Codable {
    case ignore
    case sequence
    case random
}

struct PresetDynamicsEffect: Codable {
    let effect: String
    
    let xy: [Double]?
    let ct: UInt?
    
    let effect_speed: Double?
}

// MARK: - Preset State

struct PresetState: Codable {
    let on: Bool?
    let bri: UInt?
    let xy: [Double]?
    let ct: UInt?
    
    let effect: String?
    let effect_speed: Double?
    
    let transitiontime: UInt
}

extension PresetState {
    init(from scene: CLIPScene) throws {
        // Implicitly 'on', otherwise there'd be no point to running dynamic changes
        self.on = true
        
        // Not provided in the CLIPv2 output - default is 400ms
        self.transitiontime = 4
        
        // The CLIPv2 API expects and provides independent 'brightness' values for
        // every 'color' or 'ct' entry in the scene. All entries in scenes available
        // through the Hue mobile app have the same value. As of firmware v1.222.x, the
        // Zigbee command sent out to the lights contains a single brightness value.
        // Currently, it is sufficient to pick the first available brightness value.
        if let colorBrightness = scene.palette.color.first?.dimming.brightness {
            self.bri = UInt(ceil(colorBrightness * 2.55))
        } else if let ctBrightness = scene.palette.color_temperature.first?.dimming.brightness {
            self.bri = UInt(ceil(ctBrightness * 2.55))
        } else {
            throw PresetError.notAPresetState
        }
        
        if (scene.palette.color.isEmpty) {
            self.xy = nil
        } else {
            if scene.palette.color.count == 1,
               let color = scene.palette.color.first?.color.xy {
                self.xy = [color.x, color.y]
            } else {
                throw PresetError.notAPresetState
            }
        }
        
        if (scene.palette.color_temperature.isEmpty) {
            self.ct = nil
        } else {
            if scene.palette.color_temperature.count == 1,
               let ct = scene.palette.color_temperature.first?.color_temperature.mirek {
                self.ct = ct
            } else {
                throw PresetError.notAPresetState
            }
        }
        
        if (scene.palette.effects.isEmpty && scene.palette.effects_v2.isEmpty) {
            self.effect = nil
            self.effect_speed = nil
        } else {
            if (scene.palette.effects.count == 1 && scene.palette.effects_v2.isEmpty) {
                self.effect = scene.palette.effects.first!.effect
                self.effect_speed = nil
            } else if (scene.palette.effects_v2.count == 1 && scene.palette.effects.isEmpty) {
                self.effect = scene.palette.effects_v2.first!.action.effect
                self.effect_speed = scene.palette.effects_v2.first!.action.parameters.speed
            } else {
                throw PresetError.notAPresetState
            }
        }
    }
}

// MARK: - Preset Dynamics

struct PresetDynamics: Codable {
    let bri: UInt?
    let xy: [[Double]]?
    let ct: UInt?
    let transitiontime: UInt?
    
    let effects: [PresetDynamicsEffect]?
    
    let effect_speed: Double
    let auto_dynamic: Bool
    let scene_apply: PresetDynamicsApplication
}

extension PresetDynamics {
    init(from scene: CLIPScene) throws {
        self.effect_speed = scene.speed
        self.auto_dynamic = scene.auto_dynamic
        self.scene_apply = .sequence
        
        // Not provided in the CLIPv2 output - default is 400ms
        self.transitiontime = 4
        
        // The CLIPv2 API expects and provides independent 'brightness' values for
        // every 'color' or 'ct' entry in the scene. All entries in scenes available
        // through the Hue mobile app have the same value. As of firmware v1.222.x, the
        // Zigbee command sent out to the lights contains a single brightness value.
        // Currently, it is sufficient to pick the first available brightness value.
        if let colorBrightness = scene.palette.color.first?.dimming.brightness {
            self.bri = UInt(ceil(colorBrightness * 2.55))
        } else if let ctBrightness = scene.palette.color_temperature.first?.dimming.brightness {
            self.bri = UInt(ceil(ctBrightness * 2.55))
        } else {
            throw PresetError.notAPresetDynamics
        }
        
        if (scene.palette.color.isEmpty) {
            self.xy = nil
        } else {
            // !!!: There can be no more than 9 colors
            var colors: [[Double]] = []
            for color in scene.palette.color {
                colors.append([color.color.xy.x, color.color.xy.y])
            }
            self.xy = colors
        }
        
        if (scene.palette.color_temperature.isEmpty) {
            self.ct = nil
        } else {
            if scene.palette.color_temperature.count == 1,
               let ct = scene.palette.color_temperature.first?.color_temperature.mirek {
                self.ct = ct
            } else {
                throw PresetError.notAPresetDynamics
            }
        }
        
        if (scene.palette.effects.isEmpty && scene.palette.effects_v2.isEmpty) {
            self.effects = nil
        } else {
            if (!scene.palette.effects.isEmpty && scene.palette.effects_v2.isEmpty) {
                // !!!: There can be no more than 3 effects
                var effects: [PresetDynamicsEffect] = []
                for effect in scene.palette.effects {
                    effects.append(PresetDynamicsEffect(effect: effect.effect, xy: nil, ct: nil, effect_speed: nil))
                }
                self.effects = effects
            } else if (!scene.palette.effects_v2.isEmpty && scene.palette.effects.isEmpty) {
                // !!!: There can be no more than 3 effects
                var effects: [PresetDynamicsEffect] = []
                for effect in scene.palette.effects_v2 {
                    let colors = effect.action.parameters.color?.xy
                    effects.append(PresetDynamicsEffect(effect: effect.action.effect,
                                                        xy: colors != nil ? [colors!.x, colors!.y] : nil,
                                                        ct: effect.action.parameters.color_temperature?.mirek,
                                                        effect_speed: effect.action.parameters.speed))
                }
                self.effects = effects
            } else {
                throw PresetError.notAPresetState
            }
        }
    }
}

