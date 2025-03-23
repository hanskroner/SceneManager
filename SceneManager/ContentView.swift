//
//  ContentView.swift
//  SceneManager
//
//  Created by Hans Kröner on 08/10/2023.
//

import SwiftUI

struct ContentView: View {
    @Environment(WindowItem.self) private var window
    
    @SceneStorage("inspector") private var showInspector = false
    
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
                Button(action: { }) {
                    Label("Create Scene Preset", systemImage: "rectangle.stack")
                }
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
