//
//  LightStateView.swift
//  SceneManager
//
//  Created by Hans Kröner on 16/11/2022.
//

import SwiftUI
import UniformTypeIdentifiers
import OSLog

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "light-state")

// MARK: - Views

enum Tab: Hashable {
    case sceneState
    case dynamicScene
}

struct LightStateView: View {
    var light: LightItem?
    
    @Environment(Sidebar.self) private var sidebar
    @Environment(Lights.self) private var lights
    @Environment(WindowItem.self) private var window
    
    private let _decoder = JSONDecoder()
    private let _encoder = JSONEncoder()
    
    var body: some View {
        @Bindable var window = window
        VStack(alignment: .leading) {
            
            ZStack {
                TabView(selection: $window.selectedEditorTab) {
                    SimpleJSONTextView(text: $window.stateEditorText, isEditable: true, font: .monospacedSystemFont(ofSize: 12, weight: .medium))
                        .clipped()
                        .disabled(sidebar.selectedSidebarItem == nil
                                  || sidebar.selectedSidebarItem?.kind != .scene)
                        .tabItem {
                            Text("Scene State")
                        }
                        .tag(Tab.sceneState)
                    
                    SimpleJSONTextView(text: $window.dynamicsEditorText, isEditable: true, font: .monospacedSystemFont(ofSize: 12, weight: .medium))
                        .clipped()
                        .disabled(sidebar.selectedSidebarItem == nil
                                  || sidebar.selectedSidebarItem?.kind != .scene)
                        .tabItem {
                            Text("Dynamic Scene")
                        }
                        .tag(Tab.dynamicScene)
                }
                
                // !!!: Transparent view to recieve 'PresetItem' drag'n'drops
                //      For some unknown reason, the underlying NSTextView refuses to
                //      accept drops since macOS Sequoia. This empty, transparent view
                //      is overlaid on top of SimpleJSONTextView with the sole purpose
                //      of receiving the drop of 'PresetItems'.
                Rectangle()
                    .fill(Color.white.opacity(0.0))
                    .allowsHitTesting(false)
                    .drop(if: (sidebar.selectedSidebarItem?.kind == .scene), for: PresetItem.self, action: { items, location in
                        guard let first = items.first else { return false }
                        logger.info("Dropped \(first.name)")
                        
                        switch first.state {
                        case .recall(_):
                            window.stateEditorText = first.state.json.prettyPrint()
                            window.selectedEditorTab = .sceneState
                        case .dynamic(_):
                            window.dynamicsEditorText = first.state.json.prettyPrint()
                            window.selectedEditorTab = .dynamicScene
                        }
                        
                        return true
                    })
            }
            
            HStack {
                Spacer()
                Button("Apply to Scene") {
                    switch window.selectedEditorTab {
                    case .sceneState:
                        // Modify all the lights in the scene to the attributes in the State Editor
                        guard let data = window.stateEditorText.data(using: .utf8) else {
                            // FIXME: Error handling
                            logger.error("Could not convert string to data.")
                            return
                        }
                        
                        window.clearWarnings()
                        Task {
                            let recall = try _decoder.decode(PresetState.self, from: data)
                            
                            try await window.applyState(.recall(recall), toGroupId: window.groupId!, sceneId: window.sceneId!, lightIds: lights.items.map{ $0.lightId })
                        } catch: { error in
                            logger.error("\(error, privacy: .public)")
                            
                            window.handleError(error)
                        }
                        
                    case .dynamicScene:
                        // Modify all the lights in the scene to attributes in the Dynamics Editor
                        // The order in which attributes are applied depends on some of the attributes themselves
                        guard let data = window.dynamicsEditorText.data(using: .utf8) else {
                            // FIXME: Error handling
                            logger.error("Could not convert string to data.")
                            return
                        }
                        
                        window.clearWarnings()
                        Task {
                            let dynamic = try _decoder.decode(PresetDynamics.self, from: data)
                            
                            try await window.applyState(.dynamic(dynamic), toGroupId: window.groupId!, sceneId: window.sceneId!, lightIds: lights.items.map{ $0.lightId })
                        } catch: { error in
                            logger.error("\(error, privacy: .public)")
                            
                            window.handleError(error)
                        }
                    }
                }
                .disabled(sidebar.selectedSidebarItem == nil
                          || sidebar.selectedSidebarItem?.kind != .scene
                          || (window.selectedEditorTab == .sceneState && window.stateEditorText.isEmpty)
                          || (window.selectedEditorTab == .dynamicScene && window.dynamicsEditorText.isEmpty))
                .fixedSize(horizontal: true, vertical: true)
                
                Button("Apply to Selected") {
                    guard let data = window.stateEditorText.data(using: .utf8) else {
                        // FIXME: Error handling
                        logger.error("Could not convert string to data.")
                        return
                    }
                    
                    window.clearWarnings()
                    Task {
                        let recall = try _decoder.decode(PresetState.self, from: data)
                        
                        try await window.applyState(.recall(recall), toGroupId: window.groupId!, sceneId: window.sceneId!, lightIds: lights.selectedLightItems.map{ $0.lightId })
                    } catch: { error in
                        logger.error("\(error, privacy: .public)")
                        
                        window.handleError(error)
                    }
                }
                .disabled(sidebar.selectedSidebarItem == nil
                          || sidebar.selectedSidebarItem?.kind != .scene
                          || lights.selectedLightItems.isEmpty
                          || window.stateEditorText.isEmpty
                          || window.selectedEditorTab == .dynamicScene)
                .fixedSize(horizontal: true, vertical: true)
            }
        }
        .frame(minWidth: 250)
        .padding(.bottom, 8)
        .onChange(of: light) { oldValue, newValue in
            guard let newValue else {
                window.stateEditorText = ""
                return
            }
            
            window.clearWarnings()
            Task {
                // Update the State Editor when light selection changes
                window.stateEditorText = try await window.jsonLightState(forLightId: newValue.lightId,
                                                   groupId: window.groupId,
                                                   sceneId: window.sceneId)
                
                // Switch to the State Editor if it wasn't already selected
                if ((window.stateEditorText != "") && (window.selectedEditorTab != .sceneState)) {
                    Task { @MainActor in
                        window.selectedEditorTab = .sceneState
                    }
                }
            } catch: { error in
                logger.error("\(error, privacy: .public)")
                
                window.handleError(error)
            }
        }
    }
}

// MARK: - Models

struct Dropable<T: Transferable>: ViewModifier {
    let condition: Bool
    
    let payloadType: T.Type
    let action: (_ items: [T], _ location: CGPoint) -> Bool, isTargeted: (Bool) -> Void = { _ in }
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if condition {
            content.dropDestination(for: payloadType, action: action)
        } else {
            content
        }
    }
}

extension View {
    public func drop<T: Transferable>(if condition: Bool, for payloadType: T.Type = T.self, action: @escaping (_ items: [T], _ location: CGPoint) -> Bool, isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        self.modifier(Dropable(condition: condition, payloadType: payloadType, action: action))
    }
}

// MARK: - Previews

#Preview("LightStateView") {
    let sidebar = Sidebar()
    let lights = Lights()
    let window = WindowItem()

    LightStateView(light: LightItem(lightId: 1, name: "1"))
            .frame(width: 250, height: 420, alignment: .center)
            .environment(sidebar)
            .environment(lights)
            .environment(window)
}
