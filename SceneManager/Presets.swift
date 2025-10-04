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

@Observable
final class PresetItem: Identifiable, Codable, Transferable {
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
    
    @State private var presetsSearchText: String = ""
    
    private func sectionTitle(forPresetItemGroup group: PresetItemGroup) -> String {
        return group.name.replacing("_", with: " ").capitalized
    }
    
    private var filteredPresetGroups: Binding<[PresetItemGroup]> {
        Binding {
            guard !presetsSearchText.isEmpty else { return presets.groups }
            
            var displayPresetGroups: [PresetItemGroup] = []
            
            for group in presets.groups {
                let filteredPresets = group.presets.filter {
                    $0.name.localizedCaseInsensitiveContains(presetsSearchText)
                }
                guard !filteredPresets.isEmpty else { continue }
                displayPresetGroups.append(PresetItemGroup(name: group.name,
                                                           presets: filteredPresets))
            }
            
            return displayPresetGroups
        } set: { presetGroups in
            for group in presetGroups {
                presets.groups.removeAll(where: { $0.id == group.id })
            }
            
            presets.groups.append(contentsOf: presetGroups)
        }
    }
    
    var body: some View {
        ScrollViewReader { scrollReader in
            List {
                ForEach(filteredPresetGroups, id: \.id) { $group in
                    Section {
                        ForEach($group.presets, id: \.id) { $item in
                            PresetItemView(presetItem: $item)
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                            Text(sectionTitle(forPresetItemGroup: group))
                    }
                    .listSectionSeparator(.hidden, edges: .top)
                }
            }
            .onChange(of: presets.scrollToPresetItemId) { previousItem, newItem in
                if let item = newItem {
                    withAnimation {
                        scrollReader.scrollTo(item, anchor: .center)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                SearchField(text: $presetsSearchText, prompt: "Filter Presets")
                    .image(.filter)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .frame(alignment: .top)
            }
        }
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
    
    PresetsView()
        .frame(width: 200, height: 420, alignment: .center)
        .environment(presets)
        .environment(window)
}
