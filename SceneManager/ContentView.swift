//
//  ContentView.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import SwiftUI

// MARK: - Views

struct ContentView: View {
    @EnvironmentObject private var deconzModel: deCONZClientModel
    
    @SceneStorage("inspector") private var showInspector = false
    
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
            Button(action: { withAnimation { showInspector.toggle() }}) {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
        }
    }
}

// MARK: - Previews

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
