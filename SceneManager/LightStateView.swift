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

struct LightStateView: View {
    var light: LightItem?
    
    @Environment(Sidebar.self) private var sidebar
    @Environment(Lights.self) private var lights
    @Environment(WindowItem.self) private var window
    
    @State var text: String = ""
    
    var body: some View {
//        @Bindable var deconzModel = deconzModel
        
        VStack(alignment: .leading) {
            Text("State")
                .font(.title2)
                .padding(.horizontal)
                .padding([.bottom], -4)
            
            ZStack {
                SimpleJSONTextView(text: $text, isEditable: true, font: .monospacedSystemFont(ofSize: 12, weight: .medium))
                    .clipped()
                
                // !!!: Transparent view to recieve 'PresetItem' drag'n'drops
                //      For some unknown reason, the underlying NSTextView refuses to
                //      accept drops since macOS Sequoia. This empty, transparent view
                //      is overlaid on top of SimpleJSONTextView with the sole purpose
                //      of receiving the drop of 'PresetItems'.
                Rectangle()
                    .fill(Color.white.opacity(0.0))
                    .allowsHitTesting(false)
                    .drop(if: (sidebar.selectedSidebarItem?.kind == .scene) && (!lights.selectedLightItems.isEmpty), for: PresetItem.self, action: { items, location in
                        guard let first = items.first else { return false }
                        logger.info("Dropped \(first.name)")
                        text = first.state.prettyPrint()
                        
                        return true
                    })
            }
            
            HStack {
                Spacer()
                Button("Apply to Scene") {
//                    Task {
//                        deconzModel.jsonStateText = deconzModel.lightStateText
//                        await deconzModel.modifyScene(range: .allLightsInScene)
//                    }
                }
//                .disabled(deconzModel.selectedSidebarItem == nil
//                          || deconzModel.jsonStateText.isEmpty)
                .fixedSize(horizontal: true, vertical: true)
                
                Button("Apply to Selected") {
//                    Task {
//                        deconzModel.jsonStateText = deconzModel.lightStateText
//                        await deconzModel.modifyScene(range: .selectedLightsOnly)
//                    }
                }
//                .disabled(deconzModel.selectedLightItems.isEmpty
//                          || deconzModel.jsonStateText.isEmpty)
                .fixedSize(horizontal: true, vertical: true)
            }
        }
        .frame(minWidth: 250)
        .padding(.bottom, 8)
        .onChange(of: light) { oldValue, newValue in
            guard let newValue else {
                text = ""
                return
            }
            
            Task {
                text = await window.jsonLightState(forLightId: newValue.lightId,
                                                   groupId: window.groupId,
                                                   sceneId: window.sceneId)
            }
        }
//        .disabled(deconzModel.selectedSidebarItem ==  nil || deconzModel.selectedSidebarItem?.type == .group)
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
