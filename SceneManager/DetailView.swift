//
//  DetailView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var deconzModel: deCONZClientModel
    
    @Binding var showInspector: Bool
    
    @State private var presets: [PresetItem] = [
        PresetItem(name: "Cold Bright", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "ct", ct: 333)),
        PresetItem(name: "Cold Medium", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 140, transitiontime: 4, colormode: "ct", ct: 333)),
        PresetItem(name: "Warm Bright", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "ct", ct: 346)),
        PresetItem(name: "Warm Medium", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 140, transitiontime: 4, colormode: "ct", ct: 346)),
        PresetItem(name: "Relax", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 140, transitiontime: 4, colormode: "ct", ct: 447)),
        PresetItem(name: "Nightlight", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 1, transitiontime: 4, colormode: "xy", x: 0.5618, y: 0.3985)),
        PresetItem(name: "Halloween Orange", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "xy", x: 0.5921, y: 0.3830)),
        PresetItem(name: "Halloween Purple", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "xy", x: 0.2485, y: 0.0917)),
        PresetItem(name: "Christmas Green", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "xy", x: 0.3015, y: 0.5666)),
        PresetItem(name: "Christmas Red", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "xy", x: 0.6750, y: 0.3220))
    ]
    
    var body: some View {
        HStack {
            HStack(spacing: 16) {
                LightView()
                
                LightStateView()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            if (showInspector) {
                List {
                    Section("Scene Presets") {
                        ForEach($presets, id: \.self) { preset in
                            PresetView(presetItem: preset)
                        }
                    }
                }
                .frame(minWidth: 200, maxWidth: 200, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .transition(.move(edge: .trailing))
            }
        }
    }
}

// MARK: - Previews

struct DetailView_Previews: PreviewProvider {
    static let deconzModel = deCONZClientModel()
    
    static var previews: some View {
        DetailView(showInspector: .constant(false))
            .environmentObject(deconzModel)
    }
}
