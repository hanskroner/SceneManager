//
//  Presets.swift
//  SceneManager
//
//  Created by Hans Kröner on 20/10/2023.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import OSLog
import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "presets")
private let uuidNamespace = "com.hanskroner.scenemanager.presets"

// MARK: - Presets Model

@MainActor
@Observable
class Presets {
    var groups: [PresetItemGroup] = []
    
    var scrollToPresetItemId: UUID? = nil
    
    var modelRefreshedSubscription: AnyCancellable? = nil
    
    var presetsSearchText: String = ""
    
    init() {
        modelRefreshedSubscription = PresetsModel.shared.onPresetsUpdated.sink { [weak self] groups in
            // 'groups', being an array, is a value type - but PresetItemGroup is a class (reference type).
            // Each window requires an a copy of the 'PresetItemGroup's to be able to operate on it
            // independently. The operations are commited to PresetModel, which then signals the other
            // windows when they need to update their local copies of 'PresetItemGroup's.
            self?.groups = groups.map({ group in
                let newGroup = PresetItemGroup(name: group.name)
                newGroup.presets = group.presets.map({
                    let item = PresetItem(name: $0.name, image: $0.image, state: $0.state)
                    item.url = $0.url
                    return item
                })
                return newGroup
            })
        }
    }
}

// MARK: - PresetItem Model

@Observable
class PresetItemGroup: Identifiable, Codable {
    let id: UUID
    
    let name: String
    var presets: [PresetItem]
    
    init(name: String, presets: [PresetItem] = []) {
        self.id = UUID(namespace: uuidNamespace, input: "group-\(name)")!
        
        self.name = name
        self.presets = presets
    }
    
    enum CodingKeys: CodingKey {
        case name, presets
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        presets = try container.decode([PresetItem].self, forKey: .presets)
        
        self.id = UUID(namespace: uuidNamespace, input: "group-\(name)")!
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(name, forKey: .name)
        try container.encode(presets, forKey: .presets)
    }
}

// 'Transferable' requires 'Sendable'. PresetItems are only ever mutated from the
// main actor (by the UI and 'PresetsModel'), and drag-and-drop transfers an
// encoded snapshot rather than sharing the instance across isolation domains.
@Observable
final class PresetItem: Identifiable, Codable, Transferable, @unchecked Sendable {
    let id: UUID
    
    var name: String
    var image: String?
    
    var state: PresetStateDefinition
    
    var url: URL? = nil
    
    private var _isRenaming: Bool = false
    private var _shadowName: String = ""
    
    // Store the PresetItem's name in a shadow variable when a rename operation
    // starts. Should the operation fail, the previous name can be restored by
    // calling 'restoreName'.
    var isRenaming: Bool {
        get {
            return _isRenaming
        }
        
        set {
            _isRenaming = newValue
            _shadowName = newValue ? name : _shadowName
        }
    }
    
    func restoreName() {
        name = _shadowName
    }
    
    var color: Color {
        return state.colorPalette.first?.color ?? .clear
    }
    
    init(name: String, image: String? = nil, state: PresetStateDefinition) {
        self.id = UUID(namespace: uuidNamespace, input: "\(name)")!
        
        self.name = name
        self.image = image
        self.state = state
    }
    
    enum CodingKeys: CodingKey {
        case name, image, state, dynamics
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let name = try container.decode(String.self, forKey: .name)
        self.name = name
        image = try container.decodeIfPresent(String.self, forKey: .image)
        
        let recall = try container.decodeIfPresent(PresetState.self, forKey: .state)
        let dynamic = try container.decodeIfPresent(PresetDynamics.self, forKey: .dynamics)
        
        if let recall {
            state = .recall(recall)
        } else if let dynamic {
            state = .dynamic(dynamic)
        } else {
            throw DecodingError.valueNotFound(PresetStateDefinition.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Could not decode preset state"))
        }
        
        id = UUID(namespace: uuidNamespace, input: "\(name)")!
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(image, forKey: .image)
        
        switch state {
        case .recall(let recall):
            try container.encodeIfPresent(recall, forKey: .state)
        case .dynamic(let dynamic):
            try container.encodeIfPresent(dynamic, forKey: .dynamics)
        }
    }
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .presetItem)
    }
}

extension UTType {
    static let presetItem = UTType(exportedAs: "com.hanskroner.scenemanager.preset-item")
}

// MARK: - Presets View

struct PresetsView: View {
    @Environment(Presets.self) private var presets
    
    private func sectionTitle(forPresetItemGroup group: PresetItemGroup) -> String {
        return group.name.replacing("_", with: " ").capitalized
    }
    
    private var filteredPresetGroups: Binding<[PresetItemGroup]> {
        Binding {
            guard !presets.presetsSearchText.isEmpty else { return presets.groups }
            
            var displayPresetGroups: [PresetItemGroup] = []
            
            for group in presets.groups {
                // Check if the group name matches the search text
                if group.name.localizedCaseInsensitiveContains(presets.presetsSearchText) {
                    // Include all presets from this group
                    displayPresetGroups.append(PresetItemGroup(name: group.name,
                                                               presets: group.presets))
                } else {
                    // Filter presets by name
                    let filteredPresets = group.presets.filter {
                        $0.name.localizedCaseInsensitiveContains(presets.presetsSearchText)
                    }
                    guard !filteredPresets.isEmpty else { continue }
                    displayPresetGroups.append(PresetItemGroup(name: group.name,
                                                               presets: filteredPresets))
                }
            }
            
            return displayPresetGroups
        } set: { presetGroups in
            for group in presetGroups {
                presets.groups.removeAll(where: { $0.id == group.id })
            }
            
            presets.groups.append(contentsOf: presetGroups)
        }
    }
    
    /// Where each inline section header's top edge is, in window coordinates.
    /// Headers keep the last value they reported after they scroll out of view:
    /// small for headers that left at the top, large for ones that left at the
    /// bottom, which is all 'topGroup' needs.
    @State private var headerTops: [UUID: CGFloat] = [:]
    
    /// The top bar's frame, in window coordinates.
    @State private var barFrame: CGRect = .zero
    
    /// The group named in the top bar: the last one whose inline header has
    /// reached the top of the bar. The first group has no inline header, so it's
    /// named until the second group's header gets there.
    private func topGroup(in groups: [PresetItemGroup]) -> PresetItemGroup? {
        groups.last { group in
            headerTops[group.id].map { $0 <= barFrame.minY } ?? false
        } ?? groups.first
    }
    
    /// How far the next group's inline header has pushed into the bar. The
    /// bar's title moves up by this much, so the incoming header pushes it out,
    /// and the title changes as the two line up.
    private func pushOffset(in groups: [PresetItemGroup]) -> CGFloat {
        let overlaps = groups.compactMap { headerTops[$0.id] }
            .filter { $0 > barFrame.minY && $0 < barFrame.maxY }
        guard let top = overlaps.min() else { return 0 }
        return top - barFrame.maxY
    }
    
    var body: some View {
        let groups = filteredPresetGroups.wrappedValue
        
        ScrollViewReader { scrollReader in
            // Section headers are ordinary rows rather than 'Section' headers: a
            // List's pinned headers make AppKit draw an opaque bar over them and
            // the toolbar. The pinned title lives in the top bar instead, which
            // shares the toolbar's soft scroll edge effect.
            List {
                ForEach(filteredPresetGroups, id: \.id) { $group in
                    // The first group's title is always in the top bar, so it
                    // doesn't get an inline header as well.
                    if group.id != groups.first?.id {
                        PresetsSectionHeader(title: sectionTitle(forPresetItemGroup: group))
                            // Once the bar names this group, the inline header
                            // would show through the toolbar's blur a second time.
                            .opacity(headerTops[group.id].map { $0 <= barFrame.minY } ?? false ? 0 : 1)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                                headerTops[group.id] = $0
                            }
                            .listRowSeparator(.hidden)
                    }
                    
                    ForEach($group.presets, id: \.id) { $item in
                        PresetItemView(presetItem: $item)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            // Lets the inspector's vibrant background show through the list.
            .scrollContentBackground(.hidden)
            .safeAreaBar(edge: .top) {
                if let group = topGroup(in: groups) {
                    PresetsSectionHeader(title: sectionTitle(forPresetItemGroup: group))
                        .offset(y: pushOffset(in: groups))
                        // Matches the inset List gives the inline headers' rows.
                        .padding(.horizontal, 16)
                        .clipped()
                        .background {
                            Color.clear
                                .glassEffect(.regular, in: .rect)
                                .ignoresSafeArea(edges: .top)
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                            barFrame = $0
                        }
                }
            }
            .safeAreaBar(edge: .bottom) {
                PresetsBottomBar()
            }
            .onChange(of: presets.scrollToPresetItemId) { previousItem, newItem in
                if let item = newItem {
                    withAnimation {
                        scrollReader.scrollTo(item, anchor: .center)
                    }
                }
            }
        }
        // Gives the inspector (and the part of the toolbar above it) the same
        // translucent, vibrant background the Sidebar has.
        .background {
            InspectorBackground()
                .ignoresSafeArea()
        }
    }
}

// MARK: - Presets Section Header View

/// A group's title with a divider below it. Used both inline in the list and
/// pinned in the top bar, so the two look the same.
struct PresetsSectionHeader: View {
    let title: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            
            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Inspector Background

/// The same behind-window vibrancy 'NavigationSplitView' gives its sidebar.
private struct InspectorBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Presets Bottom Bar View

/// Floating Liquid Glass bar at the bottom of the Presets list: a round
/// button to store the current state as a Preset, and a filter field.
struct PresetsBottomBar: View {
    @Environment(Presets.self) private var presets
    @Environment(Sidebar.self) private var sidebar
    @Environment(WindowItem.self) private var window
    
    @State private var isPresentingAddPreset = false
    
    private var shouldDisableAddButton: Bool {
        sidebar.selectedSidebarItem?.kind != .scene
            || (window.selectedEditorTab == .sceneState && window.stateEditorText.isEmpty)
            || (window.selectedEditorTab == .dynamicScene && window.dynamicsEditorText.isEmpty)
    }
    
    var body: some View {
        @Bindable var presets = presets
        
        // Same 18pt label + 5pt padding as 'SidebarAddButton', so both controls
        // are as tall as the filter field and sit on the same line as the
        // ones in the Sidebar and the Lights list.
        HStack(spacing: 8) {
            Button {
                isPresentingAddPreset = true
            } label: {
                Label("Store as Preset", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Store as Preset")
            .disabled(shouldDisableAddButton)
            .popover(isPresented: $isPresentingAddPreset, arrowEdge: .top) {
                AddPresetView(showingPopover: $isPresentingAddPreset)
            }
            
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                
                TextField("Filter", text: $presets.presetsSearchText)
                    .textFieldStyle(.plain)
                    .onExitCommand {
                        presets.presetsSearchText = ""
                    }
                
                if !presets.presetsSearchText.isEmpty {
                    Button {
                        presets.presetsSearchText = ""
                    } label: {
                        Label("Clear Filter", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding([.horizontal, .bottom], 10)
    }
}

// MARK: - PresetItem View

struct PresetItemView: View {
    @Environment(Presets.self) private var presets
    @Environment(WindowItem.self) private var window
    
    @Binding var presetItem: PresetItem
    
    @State private var isPresentingConfirmation: Bool = false
    
    @State private var isFocused: Bool = false
    
    func presetImage(forPresetItem item: PresetItem) -> String {
        if let image = item.image { return image }
        
        switch item.state {
        case .recall: return "scene-state"
        case .dynamic: return "scene-dynamics"
        }
    }
    
    var drawColors: Bool {
        switch presetItem.state {
        case .recall(_):
            return !(presetItem.state.effectPalette.count == 1 && presetItem.state.colorPalette.count == 1)
        default: return true
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if (presetItem.isRenaming) {
                EditableText(text: $presetItem.name, hasFocus: $isFocused, isRenaming: $presetItem.isRenaming)
                    .id(presetItem.id)
                    .font(.headline)
                    .padding([.leading, .trailing], 12)
                    .padding(.top, 32)
                    .onChange(of: isFocused) {
                        // Only act when focus is lost by the TextField the rename is happening in
                        guard isFocused == false else { return }
                        
                        // Do this first to force SwiftUI to recompute the view
                        presetItem.isRenaming = false
                        
                        window.clearWarnings()
                        do {
                            try PresetsModel.shared.renamePresetItem(presetItem)
                        } catch {
                            logger.error("\(error, privacy: .public)")
                            
                            // Restore the PresetItem's name to what it was
                            // before the rename started.
                            presetItem.restoreName()
                            
                            window.handleError(error)
                            return
                        }
                        
                        withAnimation {
                            // Sort the parent group's presets
                            for group in presets.groups {
                                if group.presets.contains(where: { $0.id == presetItem.id }) {
                                    group.presets.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                                    
                                    break
                                }
                            }
                        }
                    }
                    .onAppear {
                        isFocused = true
                    }
            } else {
                Text(presetItem.name)
                    .id(presetItem.id)
                    .foregroundColor(isDark(presetItem.color) ? .white : Color(NSColor.windowBackgroundColor))
                    .font(.headline)
                    .padding(.leading, 12)
                    .padding(.top, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            ZStack(alignment: .leading) {
                let effects = presetItem.state.effectPalette
                let colors = presetItem.state.colorPalette
                let count = effects.count + colors.count
                let spacing = CGFloat(count > 4 ? 110 / count : 26)
                
                ForEach(Array(effects.enumerated()), id: \.offset) { index, presetEffect in
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: CGFloat(index) * spacing, height: 44)
                        
                        // Unfortunate way of having to conditionally apply .colorMultiply
                        // only to effects that have a color defined.
                        if let effectColor = presetEffect.color?.color {
                            Image("effect-\(presetEffect.effect.rawValue)")
                                .resizable()
                                .scaledToFit()
                                .colorMultiply(effectColor)
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                                .shadow(color: .black, radius: 4, x: 0, y: 0)
                        } else {
                            Image("effect-\(presetEffect.effect.rawValue)")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                                .shadow(color: .black, radius: 4, x: 0, y: 0)
                        }
                    }
                    .zIndex(Double(effects.count + colors.count - index))
                }
                
                if drawColors {
                    ForEach(Array(colors.enumerated()), id: \.offset) { index, presetColor in
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: CGFloat(effects.isEmpty ? index : index + 1) * spacing, height: 44)
                            
                            Circle()
                                .fill(presetColor.color)
                                .shadow(color: .black, radius: 4, x: 0, y: 0)
                                .frame(width: 32, height: 32)
                        }
                        .zIndex(Double(colors.count - index))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background {
            Label {
                Text("")
            } icon: {
                Image(presetImage(forPresetItem: presetItem))
                    .resizable()
                    .opacity(0.6)
                    .foregroundColor(isDark(presetItem.color) ? .white : Color(NSColor.windowBackgroundColor))
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                
            }
            .frame(width: 96, height: 96)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(x: 28, y: 0)
        }
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(gradient: Gradient(colors: [presetItem.color.adjust(brightness: -0.2), presetItem.color,  presetItem.color.adjust(brightness: 0.2)]), startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .cornerRadius(8)
        .draggable(presetItem)
        .contextMenu {
            
            if let url = presetItem.url {
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }, label: {
                    Text("Show in Finder")
                })
            }
            
            Button(action: {
                presetItem.isRenaming = true
            }, label: {
                Text("Rename Preset")
            })
            
            Button(action: {
                isPresentingConfirmation = true
            }, label: {
                Text("Delete Preset")
            })
        }
        .confirmationDialog("Are you sure you want to delete '\(presetItem.name)'?", isPresented: $isPresentingConfirmation) {
            Button("Delete Preset", role: .destructive) {
                deletePresetItem(presetItem)
            }
        }
    }
    
    func deletePresetItem(_ presetItem: PresetItem) {
        window.clearWarnings()
        do {
            try PresetsModel.shared.deletePresetItem(presetItem)
        } catch {
            logger.error("\(error, privacy: .public)")
            
            window.handleError(error)
            return
        }
        
        withAnimation {
            // If the filesystem operation was successful, remove the PresetItem
            // from the parent group's presets
            for group in presets.groups {
                if group.presets.contains(where: { $0.id == presetItem.id }) {
                    group.presets.removeAll(where: { $0.id == presetItem.id })
                    
                    // If the group has no presets, remove it as well
                    if group.presets.isEmpty {
                        presets.groups.removeAll(where: { $0.id == group.id })
                    }
                    
                    break
                }
            }
        }
    }
    
    func isDark(_ color: Color) -> Bool {
        var r, g, b, a: CGFloat
        (r, g, b, a) = (0, 0, 0, 0)
        NSColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return  lum < 0.77
    }
}

// MARK: Add Preset View

struct AddPresetView: View {
    @Environment(Presets.self) private var presets
    @Environment(WindowItem.self) private var window
    
    @State private var newPresetName = ""
    
    @Binding var showingPopover: Bool
    
    private let _decoder = JSONDecoder()
    
    var body: some View {
        VStack {
            Text("Give the current State a name to store it as a Preset")
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 150, maxHeight: 40)
            
            TextField("Preset Name", text: $newPresetName)
                .frame(minWidth: 150)
            
            HStack {
                Spacer()
                Button("Store Preset") {
                    let stateDefinition: PresetStateDefinition
                    window.clearWarnings()
                    do {
                        switch window.selectedEditorTab {
                        case .sceneState:
                            guard let sceneData = window.stateEditorText.data(using: .utf8) else {
                                // FIXME: Error handling
                                logger.error("\("Could not convert string to data.", privacy: .public)")
                                return
                            }
                            
                            stateDefinition = .recall(try _decoder.decode(PresetState.self, from: sceneData))
                        case .dynamicScene:
                            guard let sceneData = window.dynamicsEditorText.data(using: .utf8) else {
                                // FIXME: Error handling
                                logger.error("\("Could not convert string to data.", privacy: .public)")
                                return
                            }
                            
                            stateDefinition = .dynamic(try _decoder.decode(PresetDynamics.self, from: sceneData))
                        }
                    } catch {
                        logger.error("\(error, privacy: .public)")
                        
                        window.handleError(error)
                        return
                    }
                    
                    // The 'custom' group represents the root of the app's 'Documents'
                    // directory and shouldn't ever be missing. All custom presets are
                    // stored here.
                    let customGroup = presets.groups.first(where: { $0.name == "custom" })!
                    
                    // If a Preset with the same name already exits in the 'custom' group,
                    // overwrite its state instead of creating a new file.
                    if let index = customGroup.presets.firstIndex(where: { $0.name == newPresetName }) {
                        window.clearWarnings()
                        // Update the state of the existing preset, but save it in case
                        // the filesystem operation fails and it needs to be reverted.
                        let existingPreset = customGroup.presets[index]
                        let currentState = existingPreset.state
                        existingPreset.state = stateDefinition
                        do {
                            existingPreset.state = stateDefinition
                            try PresetsModel.shared.savePresetItem(existingPreset)
                        } catch {
                            existingPreset.state = currentState
                            
                            logger.error("\(error, privacy: .public)")
                            
                            window.handleError(error)
                            return
                        }
                        
                        withAnimation {
                            showingPopover = false
                        }
                        
                        // FIXME: Only scroll if item isn't visible
                        presets.scrollToPresetItemId = customGroup.presets[index].id
                    } else {
                        // Create a new PresetItem and its file representation
                        let newPresetItem = PresetItem(name: newPresetName, state: stateDefinition)
                        
                        window.clearWarnings()
                        do {
                            try PresetsModel.shared.savePresetItem(newPresetItem)
                        } catch {
                            logger.error("\(error, privacy: .public)")
                            
                            window.handleError(error)
                            return
                        }
                        
                        // If the filesystem operation was successful, append the new PresetItem
                        // to the model and scroll it into view. The popover can now be dismissed.
                        customGroup.presets.append(newPresetItem)
                        
                        withAnimation {
                            // Sort the parent group's presets
                            for group in presets.groups {
                                if group.presets.contains(where: { $0.id == newPresetItem.id }) {
                                    group.presets.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                                    
                                    break
                                }
                            }
                            
                            showingPopover = false
                        }
                        
                        presets.scrollToPresetItemId = newPresetItem.id
                    }
                    
                    newPresetName = ""
                }
                .disabled(newPresetName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.vertical, 6)
        }
        .fixedSize()
        .padding()
    }
}

// MARK: - Previews

#Preview("Presets") {
    let contentURL = Bundle.main.url(forResource: "Presets", withExtension: "json")
    let contentData = try! Data(contentsOf: contentURL!)
    let presets = Presets(json: contentData)
    let window = WindowItem()
    let sidebar = Sidebar()
    
    PresetsView()
        .frame(width: 200, height: 420, alignment: .center)
        .environment(presets)
        .environment(window)
        .environment(sidebar)
}
