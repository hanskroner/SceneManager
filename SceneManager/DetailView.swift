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
    
    @State private var presets: [PresetScene] = [
        PresetScene(name: "Cold Bright", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "ct", ct: 333)),
        PresetScene(name: "Cold Medium", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 140, transitiontime: 4, colormode: "ct", ct: 333)),
        PresetScene(name: "Warm Bright", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "ct", ct: 346)),
        PresetScene(name: "Warm Medium", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 140, transitiontime: 4, colormode: "ct", ct: 346)),
        PresetScene(name: "Relax", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 140, transitiontime: 4, colormode: "ct", ct: 447)),
        PresetScene(name: "Nightlight", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 1, transitiontime: 4, colormode: "xy", x: 0.5618, y: 0.3985)),
        PresetScene(name: "Halloween Orange", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "xy", x: 0.5921, y: 0.3830)),
        PresetScene(name: "Halloween Purple", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "xy", x: 0.2485, y: 0.0917)),
        PresetScene(name: "Christmas Green", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "xy", x: 0.3015, y: 0.5666)),
        PresetScene(name: "Christmas Red", systemImage: "lightbulb.2", preset:
                        deCONZLightState(on: true, bri: 229, transitiontime: 4, colormode: "xy", x: 0.6750, y: 0.3220))
    ]
    
    var body: some View {
        HStack {
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Lights")
                        .font(.title2)
                        .padding(.horizontal)
                        .padding([.bottom], -4)
                    
                    List(deconzModel.sceneLights, id: \.self, selection: $deconzModel.selectedSceneLights) { item in
                        Text(item.name)
                    }
                    .onChange(of: deconzModel.selectedSceneLights) { newValue in
                        deconzModel.jsonStateText = deconzModel.selectedSceneLights.first?.state ?? ""
                    }
                }
                .frame(minWidth: 250)
                
                VStack(alignment: .leading) {
                    Text("State")
                        .font(.title2)
                        .padding(.horizontal)
                        .padding([.bottom], -4)
                    
                    SimpleJSONTextView(text: $deconzModel.jsonStateText, isEditable: true, font: .monospacedSystemFont(ofSize: 12, weight: .medium))
                        .onDrop(of: [PresetScene.draggableType], isTargeted: nil) { providers in
                            PresetScene.fromItemProviders(providers) { presets in
                                guard let first = presets.first else { return }
                                deconzModel.jsonStateText = first.preset.prettyPrint
                            }
                            
                            return true
                        }
                    
                    HStack {
                        Spacer()
                        Button("Apply to Group") {
                            Task {
                                await deconzModel.modifyScene(range: .allLightsInGroup)
                            }
                        }
                        .disabled(deconzModel.selectedSidebarItem == nil
                                  || deconzModel.jsonStateText.isEmpty)
                        .fixedSize(horizontal: true, vertical: true)
                        
                        Button("Apply to Selected") {
                            Task {
                                await deconzModel.modifyScene(range: .selectedLightsOnly)
                            }
                        }
                        .disabled(deconzModel.selectedSceneLights.isEmpty
                                  || deconzModel.jsonStateText.isEmpty)
                        .fixedSize(horizontal: true, vertical: true)
                    }
                }
                .frame(minWidth: 250)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            if (showInspector) {
                List {
                    Section("Scene Presets") {
                        ForEach($presets, id: \.self) { preset in
                            PresetView(preset: preset)
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

struct SceneLight: Identifiable, Hashable {
    let id: String
    var lightID: Int
    var name: String
    var state: String
}

//struct DetailView_Previews: PreviewProvider {
//    static var previews: some View {
//        DetailView(item: .constant(nil), deconzModel: nil, showInspector: .constant(false))
//    }
//}
