//
//  CLIPModels.swift
//  SceneConverter
//
//  Created by Hans Kröner on 03/04/2025.
//

import Foundation

struct CLIPScene: Codable {
    let palette: CLIPPalette
    let metadata: CLIPMetaData
    let speed: Double
    let auto_dynamic: Bool
}

struct CLIPMetaData: Codable {
    let name: String
}

struct CLIPPalette: Codable {
    let color: [CLIPColor]
    let dimming: [CLIPDimming]
    let color_temperature: [CLIPColorTemperature]
    let effects: [CLIPEffect]
    let effects_v2: [CLIPEffectv2Action]
}

struct CLIPColor: Codable {
    let color: CLIPColorColor
    let dimming: CLIPDimming
}

struct CLIPColorColor: Codable {
    let xy: CLIPColorXY
}

struct CLIPColorXY: Codable {
    let x: Double
    let y: Double
}

struct CLIPDimming: Codable {
    let brightness: Double
}

struct CLIPColorTemperature: Codable {
    let color_temperature: CLIPMirek
    let dimming: CLIPDimming
}

struct CLIPMirek: Codable {
    let mirek: Int
}

struct CLIPEffect: Codable {
    let effect: String
}

struct CLIPEffectv2Action: Codable {
    let action: CLIPEffect
}
