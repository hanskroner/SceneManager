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
                        
                        if let stateText = first.state?.prettyPrint() {
                            window.stateEditorText = stateText
                            window.selectedEditorTab = .sceneState
                        } else if let dynamicsText = first.dynamics?.prettyPrint() {
                            window.dynamicsEditorText = dynamicsText
                            window.selectedEditorTab = .dynamicScene
                        } else {
                            // FIXME: Error handling
                            logger.error("\(first.name) has no 'state' or 'dynamics'")
                        }
                        
                        return true
                    })
            }
            
            HStack {
                Spacer()
                Button("Apply to Scene") {
                    Task {
                        await window.modify(jsonLightState: window.stateEditorText, forGroupId: window.groupId!, sceneId: window.sceneId!, lightIds: lights.items.map{ $0.lightId })
                    }
                }
                .disabled(sidebar.selectedSidebarItem == nil
                          || sidebar.selectedSidebarItem?.kind != .scene
                          || window.stateEditorText.isEmpty)
                .fixedSize(horizontal: true, vertical: true)
                
                Button("Apply to Selected") {
                    Task {
                        await window.modify(jsonLightState: window.stateEditorText, forGroupId: window.groupId!, sceneId: window.sceneId!, lightIds: lights.selectedLightItems.map{ $0.lightId })
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
            
            Task {
                window.stateEditorText = await window.jsonLightState(forLightId: newValue.lightId,
                                                   groupId: window.groupId,
                                                   sceneId: window.sceneId)
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
