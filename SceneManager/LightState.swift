//
//  LightState.swift
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
    @Environment(Sidebar.self) private var sidebar
    @Environment(Lights.self) private var lights
    @Environment(WindowItem.self) private var window
    
    private let _decoder = JSONDecoder()
    private let _encoder = JSONEncoder()
    
    enum EditorField {
        case state, dynamics
    }
    
    @FocusState private var focus: EditorField?
    
    var body: some View {
        @Bindable var window = window
        VStack(alignment: .leading) {
            
            ZStack {
                TabView(selection: $window.selectedEditorTab) {
                    ZStack {
                        SimpleJSONTextView(text: $window.stateEditorText, isEditable: true, font: .monospacedSystemFont(ofSize: 12, weight: .medium))
                            .clipped()
                            .focused($focus, equals: .state)
                            .disabled(sidebar.selectedSidebarItem == nil
                                      || sidebar.selectedSidebarItem?.kind != .scene)
                        
                        if (lights.selectedLightItems.isEmpty
                            && focus != .state
                            && window.stateEditorText.isEmpty) {
                            Text("Select a light or" + (sidebar.selectedSidebarItem?.kind == .scene ? "\n type a state" : " scene"))
                                .multilineTextAlignment(.center)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tabItem {
                        Text("Scene State")
                    }
                    .tag(Tab.sceneState)
                    
                    ZStack {
                        SimpleJSONTextView(text: $window.dynamicsEditorText, isEditable: true, font: .monospacedSystemFont(ofSize: 12, weight: .medium))
                            .clipped()
                            .focused($focus, equals: .dynamics)
                            .disabled(sidebar.selectedSidebarItem == nil
                                      || sidebar.selectedSidebarItem?.kind != .scene)
                        
                        if ((sidebar.selectedSidebarItem?.kind != .scene || focus != .dynamics)
                            && window.dynamicsEditorText.isEmpty) {
                            Text((sidebar.selectedSidebarItem?.kind == .scene ? "Type a dynamic state" : "Select a scene"))
                                .multilineTextAlignment(.center)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                        
                        switch first.state {
                        case .recall(_):
                            window.selectedEditorTab = .sceneState
                            window.stateEditorText = first.state.json.prettyPrint()
                        case .dynamic(_):
                            window.selectedEditorTab = .dynamicScene
                            window.dynamicsEditorText = first.state.json.prettyPrint()
                        }
                        
                        return true
                    })
            }
        }
        .frame(minWidth: 250)
        .onChange(of: lights.selectedLightItems) { oldValue, newValue in
            let newValue = newValue.first
            
            window.clearWarnings()
            Task {
                do {
                    let selectedLightIds = newValue == nil ? [] : [newValue!.lightId]
                    try await window.updateEditors(selectedGroupId: window.groupId,
                                                   selectedSceneId: window.sceneId,
                                                   selectedLightIds: selectedLightIds)
                } catch {
                    logger.error("\(error, privacy: .public)")
                    
                    window.handleError(error)
                }
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

    LightStateView()
            .frame(width: 250, height: 420, alignment: .center)
            .environment(sidebar)
            .environment(lights)
            .environment(window)
}
