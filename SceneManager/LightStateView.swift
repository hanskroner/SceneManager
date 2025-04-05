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
    
    func applyDynamicSceneToScene() async {
        do {
            let dynamics = try JSONDecoder().decode(PresetDynamics.self, from: window.dynamicsEditorText.data(using: .utf8)!)
            
            switch dynamics.scene_state {
            case .ignore:
                // Don't update the scene attributes
                break
                
            case .apply_sequence:
                // Apply the colors/ct in the dynamic scene to the lights
                // in the scene in order
                for (index, light) in lights.items.enumerated() {
                    let state = PresetState(on: true,
                                            bri: dynamics.bri,
                                            xy: dynamics.xy != nil ? [dynamics.xy![index % dynamics.xy!.count][0], dynamics.xy![index % dynamics.xy!.count][1]] : nil,
                                            ct: dynamics.ct,
                                            transitiontime: 4)
                    
                    // Encode PresetState as JSON and get it back as a String
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let jsonData = try encoder.encode(state)
                    let jsonString = String(data: jsonData, encoding: .utf8)!
                    
                    await window.modify(jsonLightState: jsonString, forGroupId: window.groupId!, sceneId: window.sceneId!, lightIds: [light.lightId])
                }
                
            case .apply_randomized:
                for light in lights.items {
                    // Generate a random number between '0' and 'dynamics.xy.count - 1'
                    // to use as the index for the color to apply to a light.
                    var random: Int?
                    if let xy = dynamics.xy { random = Int(arc4random_uniform(UInt32(xy.count))) }
                    
                    let state = PresetState(on: true,
                                            bri: dynamics.bri,
                                            xy: random != nil ? [dynamics.xy![random!][0], dynamics.xy![random!][1]] : nil,
                                            ct: dynamics.ct,
                                            transitiontime: 4)
                    
                    // Encode PresetState as JSON and get it back as a String
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let jsonData = try encoder.encode(state)
                    let jsonString = String(data: jsonData, encoding: .utf8)!
                    
                    await window.modify(jsonLightState: jsonString, forGroupId: window.groupId!, sceneId: window.sceneId!, lightIds: [light.lightId])
                }
                
            }
        } catch {
            // FIXME: Error handling
            logger.error("\(error, privacy: .public)")
        }
    }
    
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
                        switch window.selectedEditorTab {
                        case .sceneState:
                            // Modify all the lights in the scene to the attributes in the State Editor
                            await window.modify(jsonLightState: window.stateEditorText, forGroupId: window.groupId!, sceneId: window.sceneId!, lightIds: lights.items.map{ $0.lightId })
                            
                        case .dynamicScene:
                            // Modify all the lights in the scene to attributes in the Dynamics Editor
                            // The order in which attributes are applied depends on some of the attributes themselves
                            await applyDynamicSceneToScene()
                            
                            // FIXME: Apply the Dynamic Scene
                            //        This should eventually be an API call that stores the Dynamic Scene's
                            //        state - including whether or not it should play when being recalled.
                        }
                    }
                }
                .disabled(sidebar.selectedSidebarItem == nil
                          || sidebar.selectedSidebarItem?.kind != .scene
                          || (window.selectedEditorTab == .sceneState && window.stateEditorText.isEmpty)
                          || (window.selectedEditorTab == .dynamicScene && window.dynamicsEditorText.isEmpty))
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
