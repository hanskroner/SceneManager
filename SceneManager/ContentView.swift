//
//  ContentView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

// MARK: - Views

struct ContentView: View {
    @EnvironmentObject private var deconzModel: SceneManagerModel
    
    @SceneStorage("inspector") private var showInspector = false
    
    @State private var showingPopover = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView(showInspector: $showInspector)
                .navigationTitle(deconzModel.selectedSidebarItem?.groupName ?? "Scene Manager")
                .navigationSubtitle(deconzModel.selectedSidebarItem?.sceneName ?? "No Scene Selected")
        }
        .frame(minWidth: 960, minHeight: 300)
        .background(Color(NSColor.gridColor))
        .toolbar {
            Button(action: { showingPopover = true }) {
                Label("Create Scene Preset", systemImage: "rectangle.stack")
            }
            .popover(isPresented: $showingPopover, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
                AddPresetView(showingPopover: $showingPopover)
            }
            .disabled((deconzModel.selectedSidebarItem ==  nil ||
                       deconzModel.selectedSidebarItem?.type == .group) ||
                       deconzModel.selectedLightItemIDs.isEmpty)
            .help("Store as Preset")
            
            Button(action: { withAnimation { showInspector.toggle() }}) {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .help("Hide or show the Scene Presets")
        }
    }
}

// MARK: - Previews

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
