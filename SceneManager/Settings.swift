//
//  Settings.swift
//  SceneManager
//
//  Created by Hans Kröner on 03/11/2024.
//

import SwiftUI
import OSLog
import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "settings")

struct SettingsView: View {
    @AppStorage("deconz_url") private var url = ""
    @AppStorage("deconz_key") private var key = ""
    
    private enum SettingsField {
        case url, key
    }
    
    @FocusState private var focus: SettingsField?
    
    private enum Tabs: Hashable {
        case deconz
    }
    
    private func retryConnection() {
        Task {
            do {
                RESTModel.shared.reconnect()
                
                try await RESTModel.shared.refreshCache()
            } catch {
                // FIXME: Error handling
                logger.error("\(error, privacy: .public)")
                return
            }
        }
    }
    
    var body: some View {
        TabView {
            Grid(alignment: .trailing) {
                GridRow {
                    Spacer()
                    Text("deCONZ URL:")
                    TextField("http://127.0.0.1:8080", text: $url)
                        .focused($focus, equals: .url)
                        .onSubmit(of: .text) {
                            guard url.isEmpty == false, key.isEmpty == false else { return }
                            retryConnection()
                        }
                }
                
                GridRow {
                    Spacer()
                    Text("deCONZ API Key:")
                    TextField("ABCDEF1234", text: $key)
                        .focused($focus, equals: .key)
                        .onSubmit(of: .text) {
                            guard url.isEmpty == false, key.isEmpty == false else { return }
                            retryConnection()
                        }
                }
            }
            .onChange(of: focus) { oldFocus, newFocus in
                guard url.isEmpty == false, key.isEmpty == false else { return }
                retryConnection()
            }
            .tabItem {
                Label("deCONZ", systemImage: "network")
            }
            .tag(Tabs.deconz)
        }
        .padding()
        .frame(width: 375, height: 100)
    }
}

#Preview {
    SettingsView()
}
