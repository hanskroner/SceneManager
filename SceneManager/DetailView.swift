//
//  DetailView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

struct AddLightsView: View {
    let window: NSWindow
    let deconzModel: deCONZClientModel
    
    @State var addLights = Set<LightItem>()
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Image("Icon")
                    .resizable()
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Lights to '\(deconzModel.selectedSidebarItem!.name)'")
                        .font(.system(.headline))
                }
                .padding(.top, 6)
            }
            
            // TODO: Only Groups for now
            List(deconzModel.lightsNotIn(groupID: deconzModel.selectedSidebarItem!.groupID!), id: \.self, selection: $addLights) { item in
                Text(item.name)
            }
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    window.close()
                }
                .fixedSize()
                .keyboardShortcut(.cancelAction)
                
                Button("Add \(addLights.count == 1 ? "Light" : "Lights")") {
                    // TODO: Only Groups for now
                    var groupLights = deconzModel.lightsList
                    groupLights.append(contentsOf: addLights)
                    
                    Task {
                        await deconzModel.modifyGroupLights(groupID: deconzModel.selectedSidebarItem!.groupID!, groupLights: groupLights)
                        window.close()
                    }
                }
                    .fixedSize()
                    .keyboardShortcut(.defaultAction)
                    .disabled(addLights.isEmpty)
            }
            .padding(.top, 8)
        }
    }
}

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
                    
                    List(deconzModel.lightsList, id: \.self, selection: $deconzModel.selectedLightItems) { item in
                        Text(item.name)
                    }
                    .onChange(of: deconzModel.selectedLightItems) { newValue in
                        deconzModel.jsonStateText = deconzModel.selectedLightItems.first?.state ?? ""
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        // TODO: Only Groups for now
                        if (deconzModel.selectedSidebarItem?.type == .group) {
                            LightsListBottomBar()
                        }
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
                            // FIXME: Disallow drop when disabled
                            PresetScene.fromItemProviders(providers) { presets in
                                guard let first = presets.first else { return }
                                deconzModel.jsonStateText = first.preset.prettyPrint
                            }
                            
                            return true
                        }
                    
                    HStack {
                        Spacer()
                        Button("Apply to Scene") {
                            Task {
                                await deconzModel.modifyScene(range: .allLightsInScene)
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
                        .disabled(deconzModel.selectedLightItems.isEmpty
                                  || deconzModel.jsonStateText.isEmpty)
                        .fixedSize(horizontal: true, vertical: true)
                    }
                }
                .frame(minWidth: 250)
                .padding(.bottom, 8)
                .disabled(deconzModel.selectedSidebarItem?.type == .group)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
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

struct LightsListBottomBar: View {
    @EnvironmentObject private var deconzModel: deCONZClientModel
    
    var body: some View {
        VStack {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Button(action: {
                    let window = NSWindow(
                        contentRect: .zero,
                        styleMask: [.titled, .closable],
                        backing: .buffered,
                        defer: false
                    )
                    
                    window.titlebarAppearsTransparent = true
                    
                    window.center()
                    window.isReleasedWhenClosed = false
                    
                    let view = AddLightsView(window: window, deconzModel: deconzModel)
                        .padding()
                        .frame( width: 340, height: 400)
                    
                    let hosting = NSHostingView(rootView: view)
                    window.contentView = hosting
                    hosting.autoresizingMask = [.width, .height]
                    
                    NSApp.keyWindow?.beginSheet(window)
                }) {
                    Label("", systemImage: "plus")
                        .padding([.leading, .bottom], 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .help("Add Lights")
                .disabled(deconzModel.selectedSidebarItem == nil)
                
                Button(action: {
                    Task {
                        let groupLights = deconzModel.lightsList.filter({ !deconzModel.selectedLightItems.contains($0) })
                        await deconzModel.modifyGroupLights(groupID: deconzModel.selectedSidebarItem!.groupID!, groupLights: groupLights)
                    }
                }) {
                    Label("", systemImage: "minus")
                        .padding(.bottom, 4)
                        .padding([.leading, .bottom], 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .help("Remove Lights")
                .disabled(deconzModel.selectedSidebarItem == nil ||
                          deconzModel.selectedLightItems.isEmpty)
                
                Spacer()
            }
            .background(.ultraThinMaterial)
        }
    }
}

struct LightItem: Identifiable, Hashable {
    let id: String
    var lightID: Int
    var name: String
    var state: String
}

struct DetailView_Previews: PreviewProvider {
    static let deconzModel = deCONZClientModel()
    
    static var previews: some View {
        DetailView(showInspector: .constant(false))
            .environmentObject(deconzModel)
    }
}
