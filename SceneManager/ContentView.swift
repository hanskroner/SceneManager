//
//  ContentView.swift
//  SceneManager
//
//  Created by Hans Kröner on 08/10/2023.
//

import SwiftUI

struct ContentView: View {
    @Environment(Sidebar.self) private var sidebar
    @Environment(Lights.self) private var lights
    @Environment(WindowItem.self) private var window
    
    @SceneStorage("inspector") private var showInspector = false
    
    @State private var showingPopover = false
    
    func recallSelectedScene() {
        guard let groupId = window.groupId, let sceneId = window.sceneId else { return }
        
        window.recall(groupId: groupId, sceneId: sceneId)
    }
    
    func turnSelectedGroupOff() {
        guard let groupId = window.groupId else { return }
        
        window.turnOff(groupId: groupId)
    }
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            HStack {
                HStack(spacing: 16) {
                    LightView()
                    
                    LightStateView(light: window.lights?.selectedLightItems.first)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle(window.navigationTitle ?? "Scene Manager")
            .navigationSubtitle(window.navigationSubtitle ?? "")
            .toolbar {
                Button(action: { recallSelectedScene() }) {
                    Label("Recall Scene", systemImage: "play")
                }
                .disabled(sidebar.selectedSidebarItem == nil
                          || sidebar.selectedSidebarItem?.kind != .scene)
                
                Button(action: { turnSelectedGroupOff() }) {
                    Label("Turn Group Off", systemImage: "stop")
                    
                }
                .disabled(sidebar.selectedSidebarItem == nil)
                
                Button(action: { showingPopover = true }) {
                    Label("Create Scene Preset", systemImage: "rectangle.stack")
                }
                .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                    AddPresetView(showingPopover: $showingPopover)
                }
                .disabled((sidebar.selectedSidebarItem ==  nil
                           || sidebar.selectedSidebarItem?.kind != .scene)
                           || (window.selectedEditorTab == .sceneState && window.stateEditorText.isEmpty)
                           || (window.selectedEditorTab == .dynamicScene && window.dynamicsEditorText.isEmpty))
                .help("Store as Preset")
            }
        }
        .inspector(isPresented: $showInspector) {
            PresetsView()
            .toolbar {
                ToolbarItem {
                    Spacer()
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: { withAnimation { showInspector.toggle() }}) {
                        Label("Toggle Inspector", systemImage: "sidebar.right")
                    }
                    .help("Hide or show the Scene Presets")
                }
            }
            .inspectorColumnWidth(min: 200, ideal: 200, max: 200)
        }
    }
}

#Preview {
    let sidebar = Sidebar()
    let lights = Lights()
    let presets = Presets()
    let window = WindowItem()
    
    return ContentView()
        .environment(sidebar)
        .environment(lights)
        .environment(presets)
        .environment(window)
}
