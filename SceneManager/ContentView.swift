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
                Button(action: { showingPopover = true }) {
                    Label("Create Scene Preset", systemImage: "rectangle.stack")
                }
                .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                    AddPresetView(showingPopover: $showingPopover)
                }
                .disabled((sidebar.selectedSidebarItem ==  nil
                           || sidebar.selectedSidebarItem?.kind != .scene)
                           || lights.selectedLightItems.isEmpty)
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
