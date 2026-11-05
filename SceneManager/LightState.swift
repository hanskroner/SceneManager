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
    
    /// Only a Scene's definition can be edited. For a Group (or no selection)
    /// the editors are read-only, but text can still be selected and scrolled.
    private var isEditable: Bool {
        sidebar.selectedSidebarItem?.kind == .scene
    }
    
    /// Whether the "empty definition" notice covers each editor. The editor's
    /// line numbers are hidden while it is showing.
    private var isStateNoticeVisible: Bool {
        lights.selectedLightItems.isEmpty
            && focus != .state
            && window.stateEditorText.isEmpty
    }
    
    private var isDynamicsNoticeVisible: Bool {
        (sidebar.selectedSidebarItem?.kind != .scene || focus != .dynamics)
            && window.dynamicsEditorText.isEmpty
    }
    
    private enum Constant {
        /// Keeps the first line of the editors clear of the floating tab selector.
        static let editorTopInset: CGFloat = 52
    }
    
    var body: some View {
        @Bindable var window = window
        VStack(alignment: .leading) {
            
            ZStack {
                // Both editors stay alive and only the selected one is shown.
                // Rebuilding the underlying NSTextView on every tab switch would
                // lose its undo history, selection and scroll position.
                ZStack {
                    ZStack {
                        SimpleJSONTextView(text: $window.stateEditorText, isEditable: isEditable, font: .monospacedSystemFont(ofSize: 12, weight: .medium), topContentInset: Constant.editorTopInset, showsLineNumbers: !isStateNoticeVisible)
                            .clipped()
                            .focused($focus, equals: .state)
                        
                        if isStateNoticeVisible {
                            ContentUnavailableView {
                                Label(sidebar.selectedSidebarItem?.kind == .scene ? "Empty Definition" : "No Selection",
                                      systemImage: "text.page.slash")
                            } description: {
                                Text("Select a Light or " + (sidebar.selectedSidebarItem?.kind == .scene ? "type in a State" : "Scene"))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .opacity(window.selectedEditorTab == .sceneState ? 1 : 0)
                    .allowsHitTesting(window.selectedEditorTab == .sceneState)
                    .accessibilityHidden(window.selectedEditorTab != .sceneState)
                    
                    ZStack {
                        SimpleJSONTextView(text: $window.dynamicsEditorText, isEditable: isEditable, font: .monospacedSystemFont(ofSize: 12, weight: .medium), topContentInset: Constant.editorTopInset, showsLineNumbers: !isDynamicsNoticeVisible)
                            .clipped()
                            .focused($focus, equals: .dynamics)
                        
                        if isDynamicsNoticeVisible {
                            ContentUnavailableView {
                                Label(sidebar.selectedSidebarItem?.kind == .scene ? "Empty Definition" : "No Scene Selected",
                                      systemImage: "text.page.slash")
                            } description: {
                                Text(sidebar.selectedSidebarItem?.kind == .scene ? "Type a dynamic state" : "Select a Scene")
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .opacity(window.selectedEditorTab == .dynamicScene ? 1 : 0)
                    .allowsHitTesting(window.selectedEditorTab == .dynamicScene)
                    .accessibilityHidden(window.selectedEditorTab != .dynamicScene)
                }
                // An overlay, not 'safeAreaBar': a bar reserves space and pushes the
                // editors down, while the pill should float over the text.
                .overlay(alignment: .top) {
                    EditorTabPicker(selection: $window.selectedEditorTab)
                        .padding(.top, 10)
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

// MARK: - Editor Tab Picker

/// A floating Liquid Glass pill that switches between the editor tabs. Built
/// from plain buttons, like 'LightAddRemoveButtons', so both pills match.
struct EditorTabPicker: View {
    @Binding var selection: Tab
    
    private func tabButton(_ title: LocalizedStringKey, tab: Tab) -> some View {
        Button {
            selection = tab
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(selection == tab ? .primary : .secondary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background {
                    if selection == tab {
                        Capsule().fill(.primary.opacity(0.22))
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
    
    var body: some View {
        HStack(spacing: 0) {
            tabButton("Scene State", tab: .sceneState)
            tabButton("Dynamic Scene", tab: .dynamicScene)
        }
        .padding(2)
        .glassEffect(.regular.interactive(), in: .capsule)
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
