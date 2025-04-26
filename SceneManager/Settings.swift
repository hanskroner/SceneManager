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
//    @Environment(WindowItem.self) private var window
    
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
        guard !url.isEmpty, !key.isEmpty else { return }
        
        Task { @MainActor in
//            window.clearWarnings()
        }
        
        Task {
            do {
                await RESTModel.shared.reconnect()
                try await RESTModel.shared.refreshCache()
            } catch {
                logger.error("\(error, privacy: .public)")
                
                Task { @MainActor in
//                    window.handleError(error)
                }
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
                }
                
                GridRow {
                    Spacer()
                    Text("deCONZ API Key:")
                    TextField("ABCDEF1234", text: $key)
                        .focused($focus, equals: .key)
                    
                    Button("Acquire Key") {
                        Task { @MainActor in
//                            window.clearWarnings()
                        }
                        
                        Task {
                            do {
                                // Ensure the RESTModel.shared object has a client
                                // configured to the URL in the 'url' TextField.
                                await RESTModel.shared.reconnect()
                                
                                key = try await RESTModel.shared.createAPIKey()
                            } catch {
                                logger.error("\(error, privacy: .public)")
                                
                                Task { @MainActor in
//                                    window.handleError(error)
                                }
                            }
                        }
                    }
                }
            }
            .onSubmit(of: .text) {
                retryConnection()
            }
            .onChange(of: focus) { oldFocus, newFocus in
                retryConnection()
            }
            .tabItem {
                Label("deCONZ", systemImage: "network")
            }
            .tag(Tabs.deconz)
        }
        .padding()
        .frame(width: 400, height: 100)
    }
}

#Preview {
    SettingsView()
}
