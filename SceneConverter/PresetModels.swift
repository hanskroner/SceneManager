//
//  PresetModels.swift
//  SceneConverter
//
//  Created by Hans Kröner on 03/04/2025.
//

import Foundation

enum PresetError: LocalizedError {
    case notAPresetState
    case notAPresetDynamics
    
    var errorDescription: String? {
        switch self {
        case .notAPresetState:
            return "Not a PreseState"
        case .notAPresetDynamics:
            return "Not a PreseDynamics"
        }
    }
}

struct Preset: Codable {
    let name: String
    let state: PresetState?
    let dynamics: PresetDynamics?
}

struct PresetState: Codable {
    let on: Bool?
    let bri: Int?
    let xy: [Double]?
    let ct: Int?
    
    let transitiontime: Int
}

struct PresetDynamics: Codable {
    let bri: Int?
    let xy: [[Double]]?
    let ct: Int?
    
    let effect_speed: Double
    let auto_dynamic: Bool
}

extension Preset {
    init(from scene: CLIPScene) throws {
        self.name = scene.metadata.name
        
        self.state = try? PresetState(from: scene)
        
        // If 'state' was parsed succesfully, don't duplicate
        // its values in 'dynamics'
        if self.state == nil {
            self.dynamics = try? PresetDynamics(from: scene)
        } else {
            self.dynamics = nil
        }
        
    }
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
            self.bri = Int(colorBrightness)
        } else if let ctBrightness = scene.palette.color_temperature.first?.dimming.brightness {
            self.bri = Int(ctBrightness)
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
    }
}

extension PresetDynamics {
    init(from scene: CLIPScene) throws {
        self.effect_speed = scene.speed
        self.auto_dynamic = scene.auto_dynamic
        
        // The CLIPv2 API expects and provides independent 'brightness' values for
        // every 'color' or 'ct' entry in the scene. All entries in scenes available
        // through the Hue mobile app have the same value. As of firmware v1.222.x, the
        // Zigbee command sent out to the lights contains a single brightness value.
        // Currently, it is sufficient to pick the first available brightness value.
        if let colorBrightness = scene.palette.color.first?.dimming.brightness {
            self.bri = Int(colorBrightness)
        } else if let ctBrightness = scene.palette.color_temperature.first?.dimming.brightness {
            self.bri = Int(ctBrightness)
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
    }
}
