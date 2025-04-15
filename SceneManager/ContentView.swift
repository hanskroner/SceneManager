//
//  ContentView.swift
//  SceneManager
//
//  Created by Hans Kröner on 08/10/2023.
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "content-view")

struct ContentView: View {
    @Environment(Sidebar.self) private var sidebar
    @Environment(Lights.self) private var lights
    @Environment(WindowItem.self) private var window
    
    @Environment(\.appearsActive) private var appearsActive
    
    @SceneStorage("inspector") private var showInspector = false
    
    @State private var showingPopover = false
    
    func recallSelectedScene() {
        guard let groupId = window.groupId, let sceneId = window.sceneId else { return }
        
        Task {
            try await window.recall(groupId: groupId, sceneId: sceneId)
        } catch: { error in
            // FIXME: Missing error alert
            logger.error("\(error, privacy: .public)")
            #warning("Missing Error Alert")
        }
    }
    
    func turnSelectedGroupOff() {
        guard let groupId = window.groupId else { return }
        
        Task {
            try await window.turnOff(groupId: groupId)
        } catch: { error in
            // FIXME: Missing error alert
            logger.error("\(error, privacy: .public)")
            #warning("Missing Error Alert")
        }
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
            .navigationTitle("")
            .navigationSubtitle("")
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    VStack(alignment: .leading, spacing: 0) {
                        if (window.navigationSubtitle?.isEmpty ?? true) {
                            Text(window.navigationTitle ?? "Scene Manager")
                                .foregroundStyle(appearsActive ? .primary : Color(.disabledControlTextColor))
                                .font(.title3)
                                .fontWeight(.bold)
                                .padding(0)
                        } else {
                            Text(window.navigationTitle ?? "Scene Manager")
                                .foregroundStyle(appearsActive ? .primary : Color(.disabledControlTextColor))
                                .font(.headline)
                                .fontWeight(.bold)
                                .padding(0)
                            
                            Text(window.navigationSubtitle ?? "")
                                .foregroundStyle(appearsActive ? .secondary : Color(.disabledControlTextColor))
                                .font(.subheadline)
                                .fontWeight(.regular)
                                .padding(0)
                        }
                    }
                    
                    if (window.hasWarning) {
                        Button(action: { }) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .resizable()
                                .scaledToFit()
                                .symbolRenderingMode(.multicolor)
                                .frame(width: 16, height: 16)
                        }
                    }
                }
                
                ToolbarItemGroup(placement: .primaryAction) {
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
