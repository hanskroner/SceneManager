//
//  Presets.swift
//  SceneManager
//
//  Created by Hans Kröner on 20/10/2023.
//

import SwiftUI
import UniformTypeIdentifiers
import OSLog
import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "presets")

// MARK: - Presets Model

@Observable
class Presets {
    var groups: [PresetItemGroup] = []
    
    var scrollToPresetItemId: UUID? = nil
    
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    init() {
        // Pretty-print JSON output
        encoder.outputFormatting = .prettyPrinted
        
        do {
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let documentsContents = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                
                if documentsContents.isEmpty {
                    try copyFilesFromBundleToDocumentsDirectoryConformingTo(.json)
                }
                
                groups = try loadPresetItemsFromDocumentsDirectory()
            }
        } catch DecodingError.typeMismatch(_, let context) {
            logger.error("\(context.debugDescription, privacy: .public)")
        } catch {
            logger.error("\(error, privacy: .public)")
        }
    }
    
    func copyFilesFromBundleToDocumentsDirectoryConformingTo(_ fileType: UTType) throws {
        if let resPath = Bundle.main.resourcePath {
            let dirContents = try FileManager.default.contentsOfDirectory(atPath: resPath)
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            
            var filteredFiles = [String]()
            for (fileExtension) in fileType.tags[.filenameExtension] ?? [] {
                filteredFiles.append(contentsOf: dirContents.filter { $0.contains(fileExtension) })
            }
            
            for (fileName) in filteredFiles {
                if let documentsURL = documentsURL {
                    let sourceURL = URL(fileURLWithPath: Bundle.main.resourcePath!).appendingPathComponent(fileName, conformingTo: fileType)
                    let destURL = documentsURL.appendingPathComponent(fileName)
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
            }
        }
    }
    
    private func filesInDocumentsDirectoryConformingTo(_ fileType: UTType) throws -> [URL] {
        var fileURLs = [URL]()
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return fileURLs }
        
        // Add files for the Documents directory
        let dirContents = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        for (fileExtension) in fileType.tags[.filenameExtension] ?? [] {
            fileURLs.append(contentsOf: dirContents.filter{ $0.absoluteString.contains(fileExtension) })
        }
        
        // Add files for each sub directory in the Documents directory
        // This is quicker and simpler than performing deep enumeration using
        // a method like 'enumeratorAtURL'.
        let dirs = try dirContents.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false }
        for (dirURL) in dirs {
            let dirContents = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for (fileExtension) in fileType.tags[.filenameExtension] ?? [] {
                fileURLs.append(contentsOf: dirContents.filter{ $0.absoluteString.contains(fileExtension) })
            }
        }
        
        return fileURLs
    }
    
    enum PresetFileError: Error {
        case noURLError(String)
    }
    
    private func urlForPresetItem(_ presetItem: PresetItem) throws -> URL {
        // Create file name from Preset name
        let fileName = presetItem.name.lowercased().replacing(" ", with: "_").appending(".json")
        
        let url = presetItem.url?.deletingLastPathComponent().appendingPathComponent(fileName)
        
        // If the URL is nil, this PresetItem doesn't have a file representation.
        // Its URL would be the base 'Documents' directory with 'fileName' appended to it.
        if url == nil {
            guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw PresetFileError.noURLError("Could not get URL for '\(presetItem.name)'")
            }
            
            return documentsURL.appendingPathComponent(fileName)
        }
        
        guard let url else {
            throw PresetFileError.noURLError("Could not get URL for '\(presetItem.name)'")
        }
        
        return url
    }
    
    func loadPresetItemsFromDocumentsDirectory() throws -> [PresetItemGroup] {
        // Use a temporary Dictionary to store the Presets
        // Appending a PresetItem into the array that belongs to subdirectory
        // becomes a bit less of a hassle with Dictionaries
        var presetDirs: [String: [PresetItem]] = [:]
        
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        
        let presetFiles = try filesInDocumentsDirectoryConformingTo(.json)
        for (presetFile) in presetFiles {
            // Check if this preset file is in a subdirectory
            let subDir: String
            if (presetFile.deletingLastPathComponent().lastPathComponent != documentsURL.lastPathComponent) {
                subDir = presetFile.deletingLastPathComponent().lastPathComponent
            } else {
                subDir = "custom"
            }
            
            // Decode the preset file's contents and add them to Preset Dictionary
            let json = try String(contentsOf: presetFile, encoding: .utf8)
            let presetItem = try decoder.decode(PresetItem.self, from: json.data(using: .utf8)!)
            presetItem.url = presetFile
            presetDirs[subDir, default: []].append(presetItem)
        }
        
        // Re-pack the dictionary into a sorted Array of PresetItemGroup
        // The presets in each group are also sorted. The 'custom' group
        // is included last, and as the first group.
        var presetGroups: [PresetItemGroup] = []
        let withoutCustom = presetDirs.filter { $0.key != "custom" }
        for (group, presets) in withoutCustom.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            presetGroups.append(PresetItemGroup(name: group,
                                                presets: presets.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })))
        }
        
        if let customGroup = presetDirs["custom"] {
            presetGroups.insert(PresetItemGroup(name: "custom",
                                                presets: customGroup.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })), at: 0)
        }
        
        return presetGroups
    }
    
    func savePresetItemToDocumentsDirectory(_ presetItem: PresetItem) throws {
        let fileContents = try encoder.encode(presetItem)
        let destURL = try urlForPresetItem(presetItem)
        try fileContents.write(to: destURL)
    }
    
    func renamePresetItemInDocumentsDirectory(_ presetItem: PresetItem) throws {
      guard let file = presetItem.url else { return }
        
        let newFileURL = try urlForPresetItem(presetItem)
        var previousFileURL = file
        
        var resourceValues = URLResourceValues()
        resourceValues.name = newFileURL.lastPathComponent
        presetItem.url = newFileURL
        
        try previousFileURL.setResourceValues(resourceValues)
        try savePresetItemToDocumentsDirectory(presetItem)
    }
    
    func deletePresetItemInDocumentsDirectory(_ presetItem: PresetItem) throws {
        guard let url = presetItem.url else {
            throw PresetFileError.noURLError("Could not get URL for '\(presetItem.name)'")
        }
        
        try FileManager.default.removeItem(at: url)
        
        // FIXME: Remove the directory if empty
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let subdirURL = url.deletingLastPathComponent()
        guard documentsURL != subdirURL else { return }
        
        // Add files for the Documents directory
        let dirContents = try FileManager.default.contentsOfDirectory(at: subdirURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        if dirContents.isEmpty {
            try FileManager.default.removeItem(at: subdirURL)
        }
    }
}

// MARK: - PresetItem Model

@Observable
class PresetItemGroup: Identifiable, Codable {
    let id: UUID = UUID()
    
    let name: String
    var presets: [PresetItem]
    
    init(name: String, presets: [PresetItem] = []) {
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
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(name, forKey: .name)
        try container.encode(presets, forKey: .presets)
    }
}

@Observable
class PresetItem: Identifiable, Codable, Transferable {
    let id: UUID = UUID()
    
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
        self.name = name
        self.image = image
        self.state = state
    }
    
    enum CodingKeys: CodingKey {
        case name, image, state, dynamics
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
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
    static var presetItem = UTType(exportedAs: "com.hanskroner.scenemanager.preset-item")
}

// MARK: - Presets View

struct PresetsView: View {
    @Environment(Presets.self) private var presets
    
    @State private var presetsSearchText: String = ""
    
    private func sectionTitle(forPresetItemGroup group: PresetItemGroup) -> String {
        return group.name.replacing("_", with: " ").capitalized
    }
    
    var body: some View {
        @Bindable var presets = presets
        
        var filteredPresetGroups: [PresetItemGroup] {
            guard !presetsSearchText.isEmpty else { return presets.groups }
            
            var displayPresetGroups: [PresetItemGroup] = []
            
            // Filter
            for group in presets.groups {
                let filteredPresets = group.presets.filter {
                    $0.name.localizedCaseInsensitiveContains(presetsSearchText)
                }
                guard !filteredPresets.isEmpty else { continue }
                displayPresetGroups.append(PresetItemGroup(name: group.name,
                                                           presets: filteredPresets))
            }
    
            return displayPresetGroups
        }
        
        ScrollViewReader { scrollReader in
            List {
                // Empty section to keep filter results from "floating" up
                // and hiding under the search bar.
                Section { }
                
                ForEach(filteredPresetGroups, id: \.id) { group in
                    Section {
                        ForEach(group.presets, id: \.id) { item in
                            PresetItemView(presetItem: item)
                        }
                    } header: {
                        // Offset the list section
                        // This allows the list to scroll under the search bar
                        // added by the overlay, without being under it initially.
                        // All sections need to be offset or they'll "float" to the
                        // top when scrolling, overlapping the search bar.
                            Text(sectionTitle(forPresetItemGroup: group))
                                .padding(.top, 38)
                    }
                }
            }
            .onChange(of: presets.scrollToPresetItemId) { previousItem, newItem in
                if let item = newItem {
                    withAnimation {
                        scrollReader.scrollTo(item, anchor: .center)
                    }
                }
            }
            .overlay {
                SearchField(text: $presetsSearchText, prompt: "Filter Presets")
                    .image(.filter)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

// MARK: - PresetItem View

extension Color {
    func adjust(hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, opacity: CGFloat = 1) -> Color {
        let color = NSColor(self)
        var currentHue: CGFloat = 0
        var currentSaturation: CGFloat = 0
        var currentBrigthness: CGFloat = 0
        var currentOpacity: CGFloat = 0

        color.getHue(&currentHue, saturation: &currentSaturation, brightness: &currentBrigthness, alpha: &currentOpacity)
        
        return Color(hue: currentHue + hue, saturation: currentSaturation + saturation, brightness: currentBrigthness + brightness, opacity: currentOpacity + opacity)
    }
}

struct PresetItemView: View {
    @Environment(Presets.self) private var presets
    @Environment(WindowItem.self) private var window
    
    @State var presetItem: PresetItem
    
    @State private var isPresentingConfirmation: Bool = false
    
    @FocusState private var isFocused: Bool
    
    func presetImage(forPresetItem item: PresetItem) -> String {
        if let image = item.image { return image }
        
        switch item.state {
        case .recall: return "scene-state"
        case .dynamic: return "scene-dynamics"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if (presetItem.isRenaming) {
                TextField("", text: $presetItem.name)
                    .id(presetItem.id)
                    .font(.headline)
                    .padding([.leading, .trailing], 12)
                    .padding(.top, 32)
                    .focused($isFocused)
                    .onChange(of: isFocused) {
                        // Only act when focus is lost by the TextField the rename is happening in
                        guard isFocused == false else { return }
                        
                        // Do this first to force SwiftUI to recompute the view
                        presetItem.isRenaming = false
                        
                        window.clearWarnings()
                        do {
                            try presets.renamePresetItemInDocumentsDirectory(presetItem)
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
                let spacing = CGFloat(count > 5 ? 130 / count : 26)
                
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
            try presets.deletePresetItemInDocumentsDirectory(presetItem)
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
    
    private let _encoder = JSONEncoder()
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
                                logger.error("Could not convert string to data.")
                                return
                            }
                            
                            stateDefinition = .recall(try _decoder.decode(PresetState.self, from: sceneData))
                        case .dynamicScene:
                            guard let sceneData = window.dynamicsEditorText.data(using: .utf8) else {
                                // FIXME: Error handling
                                logger.error("Could not convert string to data.")
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
                        do {
                            try presets.savePresetItemToDocumentsDirectory(customGroup.presets[index])
                        } catch {
                            logger.error("\(error, privacy: .public)")
                            
                            window.handleError(error)
                            return
                        }
                        
                        // If the filesystem operation was successful, update the PresetItem
                        // in the model and scroll it into view. The popover can now be dismissed.
                        
                        withAnimation {
                            customGroup.presets[index].state = stateDefinition
                            showingPopover = false
                        }
                        
                        // FIXME: Only scroll if item isn't visible
                        presets.scrollToPresetItemId = customGroup.presets[index].id
                    } else {
                        // Create a new PresetItem and its file representation
                        let newPresetItem = PresetItem(name: newPresetName, state: stateDefinition)
                        
                        window.clearWarnings()
                        do {
                            try presets.savePresetItemToDocumentsDirectory(newPresetItem)
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
            .padding(.top, 6)
        }
        .padding()
    }
}

// MARK: - Previews

#Preview("Presets") {
        let contentURL = Bundle.main.url(forResource: "Presets", withExtension: "json")
        let contentData = try! Data(contentsOf: contentURL!)
        let presets = Presets(json: contentData)
        
        return PresetsView()
            .frame(width: 200, height: 420, alignment: .center)
            .environment(presets)
    
}
