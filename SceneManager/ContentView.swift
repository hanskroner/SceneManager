//
//  ContentView.swift
//  SceneManager
//
//  Created by Hans Kröner on 08/10/2023.
//

import SwiftUI
import OSLog
import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "content-view")

struct ContentView: View {
    @State private var sidebar = Sidebar()
    @State private var lights = Lights()
    @State private var presets = Presets()
    
    @State private var window = WindowItem()
    
//    @Environment(Sidebar.self) private var sidebar
//    @Environment(Lights.self) private var lights
//    @Environment(WindowItem.self) private var window
    
    @Environment(\.appearsActive) private var appearsActive
    
    @SceneStorage("inspector") private var showInspector = false
    
    @State private var showingPopover = false
    
    func recallSelectedScene() {
        guard let groupId = window.groupId, let sceneId = window.sceneId else { return }
        
        window.clearWarnings()
        Task {
            do {
                try await RESTModel.shared.recallScene(groupId: groupId, sceneId: sceneId)
            } catch {
                logger.error("\(error, privacy: .public)")
                
                window.handleError(error)
            }
        }
    }
    
    func turnSelectedGroupOff() {
        guard let groupId = window.groupId else { return }
        
        window.clearWarnings()
        Task {
            do {
                try await RESTModel.shared.modifyGroupState(groupId: groupId, lightState: LightState(on: false))
            } catch {
                logger.error("\(error, privacy: .public)")
                
                window.handleError(error)
            }
        }
    }
    
    var body: some View {
        @Bindable var window = window
        
        NavigationSplitView {
            SidebarView()
        } detail: {
            HStack {
                HStack(spacing: 16) {
                    LightView()
                    
                    LightStateView()
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
                        Button(action: { window.isShowingWarning = true }) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .resizable()
                                .scaledToFit()
                                .symbolRenderingMode(.multicolor)
                                .frame(width: 16, height: 16)
                        }
                        .popover(isPresented: $window.isShowingWarning, arrowEdge: .bottom) {
                            WarningView(showingPopover: $window.isShowingWarning)
                                .padding(4)
                                // .presentationBackground doesn't color the popover's arrow
                                // create a background view instead, and pad it to cover the
                                // arrow instead.
                                // .presentationBackground(.yellow)
                                .background(Color.yellow.padding(-80))
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
        .sheet(isPresented: $window.isPresentingStartupConfiguration) {
            LightConfigurationView()
                .environment(window)
                .frame(width: 680)
                .padding(12)
        }
        .confirmationDialog("Are you sure you want to delete \(window.phosconKeys.count) Phoscon keys?", isPresented: $window.isPresentingPhosconDelete) {
            Button("Delete \(window.phosconKeys.count) Keys", role: .destructive) {
                // Call on the REST API to perform deletion
                window.clearWarnings()
                Task {
                    do {
                        for key in window.phosconKeys {
                            try await RESTModel.shared.deleteAPIKey(key: key)
                        }
                    } catch {
                        logger.error("\(error, privacy: .public)")
                        
                        window.handleError(error)
                    }
                }
            }
        }
        .task {
            window.clearWarnings()
            do {
                window.sidebar = sidebar
                window.lights = lights
                
                try PresetsModel.shared.loadPresetItems()
                try await RESTModel.shared.refreshCache()
            } catch {
                logger.error("\(error, privacy: .public)")
                
                window.handleError(error)
            }
        }
        .focusedSceneValue(\.activeWindow, window)
        .environment(window)
        .environment(sidebar)
        .environment(lights)
        .environment(presets)
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
