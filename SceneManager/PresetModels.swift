//
//  PresetModels.swift
//  SceneManager
//
//  Created by Hans Kröner on 08/04/2025.
//

import SwiftUI
import OSLog
import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "preset-models")

protocol JSONExportable: Codable {
    var json: JSON { get }
}

enum PresetStateDefinition: PresetPalette, JSONExportable {
    case recall(PresetState)
    case dynamic(PresetDynamics)
    
    var colorPalette: [PresetPaletteColor] {
        switch self {
        case .recall(let recall): return recall.colorPalette
        case .dynamic(let dynamic): return dynamic.colorPalette
        }
    }
    
    var effectPalette: [PresetPaletteEffect] {
        switch self {
        case .recall(let recall): return recall.effectPalette
        case .dynamic(let dynamic): return dynamic.effectPalette
        }
    }
    
    var json: JSON {
        get {
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            do {
                let jsonData: Data
                switch self {
                case .recall(let recall):
                    jsonData = try encoder.encode(recall)
                case .dynamic(let dynamic):
                    jsonData = try encoder.encode(dynamic)
                }
                
                return try decoder.decode(JSON.self, from: jsonData)
            } catch {
                logger.error("\(error, privacy: .public)")
                return .null
            }
        }
    }
}

enum PresetPaletteColorKind {
    case ct
    case xy
}

struct PresetPaletteColor {
    let color: Color
    let kind: PresetPaletteColorKind
}

enum PresetPaletteEffectKind: String {
    case candle
    case cosmos
    case enchant
    case fire
    case glisten
    case opal
    case prism
    case sparkle
    case sunbeam
    case underwater
}

struct PresetPaletteEffect {
    let effect: PresetPaletteEffectKind
    let color: PresetPaletteColor?
}

protocol PresetPalette {
    var colorPalette: [PresetPaletteColor] { get }
    var effectPalette: [PresetPaletteEffect] { get }
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

struct PresetState: Codable, PresetPalette {
    let on: Bool?
    let bri: UInt?
    let xy: [Double]?
    let ct: UInt?
    
    let effect: String?
    let effect_speed: Double?
    
    let transitiontime: UInt
    
    // MARK: Preset State Palette
    
    var colorPalette: [PresetPaletteColor] {
        if let xy, xy.count == 2 {
            let xyColor = SceneManager.color(fromXY: CGPoint(x: xy[0], y: xy[1]), brightness: 0.5)
            return [PresetPaletteColor(color: Color(xyColor), kind: .xy)]
        } else if let ct {
            guard let ctColor = SceneManager.color(fromMired: Int(ct)) else {
                logger.error("'ct': \(ct, privacy: .public) is not convertible to color.")
                return []
            }
            
            return [PresetPaletteColor(color: Color(ctColor), kind: .ct)]
        }
        
        return []
    }
    
    var effectPalette: [PresetPaletteEffect] {
        guard let effect else { return [] }
        guard let presetEffect = PresetPaletteEffectKind(rawValue: effect) else {
            logger.error("Unknown effect '\(effect, privacy: .public)'.")
            return []
        }
        
        let presetColor = colorPalette
        return [PresetPaletteEffect(effect: presetEffect, color: colorPalette.isEmpty ? nil : presetColor[0])]
    }
}

// MARK: - Preset Dynamics

struct PresetDynamics: Codable, PresetPalette {
    let bri: UInt?
    let xy: [[Double]]?
    let ct: UInt?
    
    let effects: [PresetDynamicsEffect]?
    
    let effect_speed: Double
    let auto_dynamic: Bool
    let scene_apply: PresetDynamicsApplication
    
    // MARK: Preset Dynamics Palette
    
    var colorPalette: [PresetPaletteColor] {
        var dynamicsColors: [PresetPaletteColor] = []
        
        if let xy {
            for color in xy {
                let xyColor = SceneManager.color(fromXY: CGPoint(x: color[0], y: color[1]), brightness: 0.5)
                dynamicsColors.append(PresetPaletteColor(color: Color(xyColor), kind: .xy))
            }
        } else if let ct {
            guard let ctColor = SceneManager.color(fromMired: Int(ct)) else {
                logger.error("'ct': \(ct, privacy: .public) is not convertible to color.")
                return []
            }
            
            return [PresetPaletteColor(color: Color(ctColor), kind: .ct)]
        }
        
        return dynamicsColors
    }
    
    var effectPalette: [PresetPaletteEffect] {
        guard let effects else { return [] }
        
        var dynamicsEffects: [PresetPaletteEffect] = []
        
        for effect in effects {
            guard let presetEffect = PresetPaletteEffectKind(rawValue: effect.effect) else {
                logger.error("Unknown effect '\(effect.effect, privacy: .public)'.")
                continue
            }
            
            if let xy = effect.xy, xy.count == 2 {
                let xyColor = SceneManager.color(fromXY: CGPoint(x: xy[0], y: xy[1]), brightness: 0.5)
                dynamicsEffects.append(PresetPaletteEffect(effect: presetEffect, color: PresetPaletteColor(color: Color(xyColor), kind: .xy)))
            } else if let ct = effect.ct {
                guard let ctColor = SceneManager.color(fromMired: Int(ct)) else {
                    logger.error("'ct': \(ct, privacy: .public) is not convertible to color.")
                    continue
                }
                
                dynamicsEffects.append(PresetPaletteEffect(effect: presetEffect, color: PresetPaletteColor(color: Color(ctColor), kind: .ct)))
            }
        }
        
        return dynamicsEffects
    }
}
