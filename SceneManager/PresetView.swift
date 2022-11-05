//
//  PresetView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

struct Preset: Hashable, Decodable, Encodable {
    var bri: Int
    var on: Bool
    var transitiontime: Int
    var colormode: String
    var ct: Int?
    var x: Double?
    var y: Double?
}

struct PresetScene: Hashable, Decodable, Encodable {
    var name: String
    var systemImage: String
    var preset: Preset
}

struct PresetView: View {
    @Binding var preset: PresetScene
    
    var body: some View {
        VStack {
            Label("", systemImage: preset.systemImage)
                .foregroundColor(.primary)
                .font(.system(size: 24))
            Text(preset.name)
                .font(.headline)
                .padding(.top, 4)
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
        .background(colorForPreset(preset: preset.preset))
        .cornerRadius(8)
    }
    
    func colorForPreset(preset: Preset) -> Color {
        switch preset.colormode {
        case "ct":
            return Color(colorFromMired(mired: preset.ct!)!)
        case "xy":
            return Color(colorFromXY(point: CGPoint(x: preset.x!, y: preset.y!), brightness: 1.0))
        default:
            return Color(.black)
        }
    }
}
