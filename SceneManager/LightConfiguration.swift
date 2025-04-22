//
//  LightConfiguration.swift
//  SceneManager
//
//  Created by Hans Kröner on 18/04/2025.
//

import SwiftUI
import OSLog
import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "light-configuration")

struct LightConfigurationView: View {
    @Environment(WindowItem.self) private var window
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var lightsConfiguration: [LightConfiguration] = []
    @State private var filterLightNames: String = ""
    
    @State private var isLoading = true
    @State private var hasError = true
    
    private var filteredLightsConfiguration: Binding<[LightConfiguration]> {
        Binding {
            guard !filterLightNames.isEmpty else {
                return lightsConfiguration.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
            
            return lightsConfiguration.filter({ $0.name.localizedCaseInsensitiveContains(filterLightNames) })
                .sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        } set: { configurations in
            for configuration in configurations {
                lightsConfiguration.removeAll(where: { $0.id == configuration.id })
            }
            
            lightsConfiguration.append(contentsOf: configurations)
        }
    }
    
    private var filteredLightsExecuteIfOff: Binding<[Bool]> {
        Binding {
            var boolArray: [Bool] = []
            filteredLightsConfiguration.wrappedValue.forEach {
                boolArray.append($0.bri.executeIfOff)
                boolArray.append($0.color.executeIfOff)
            }
            return boolArray
        } set: { value in
            // Do the operations on a local copy to prevent redraws
            // in the middle of updating.
            var localCopy = filteredLightsConfiguration.wrappedValue
            for index in stride(from: 0, to: value.count, by: 2) {
                localCopy[index / 2].bri.executeIfOff = value[index]
                localCopy[index / 2].color.executeIfOff = value[index]
            }
            
            filteredLightsConfiguration.wrappedValue = localCopy
        }
    }
    
    @State private var globalOn: String = ""
    @State private var globalBri: String = ""
    @State private var globalCt: String = ""
    @State private var globalXy: String = ""
    
    // Progress reporting
    @State private var isPresentingProgress = false
    @State private var progressValue = 0.0
    @State private var progressTotal = 100.0
    @State private var shouldCancel = false
    
    private func configureLights(_ lights: [LightConfiguration]) async throws {
        shouldCancel = false
        
        for (index, configuration) in lights.enumerated() {
            guard !shouldCancel else { return }
            
            do {
                try await RESTModel.shared.setLightConfiguration(configuration)
            } catch {
                shouldCancel = true
                throw error
            }
            
            try await Task.sleep(nanoseconds: UInt64(0.3 * Double(NSEC_PER_SEC)))
            progressValue = Double(index + 1)
        }
        
        return
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Configuration Values")
            
            HStack(alignment: .top, spacing: 0) {
                Toggle(sources: filteredLightsConfiguration, isOn: \.isEnabled) { }
                    .toggleStyle(.checkbox)
                    .padding(.vertical, 4)
                
                SearchField(text: $filterLightNames, prompt: "Filter Lights")
                    .image(.filter)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 240)
                
                VStack(alignment: .leading) {
                    Grid(alignment: .leading) {
                        GridRow {
                            Text("'on':")
                            TextField("previous", text: $globalOn)
                                .onChange(of: globalOn) { previousValue, newValue in
                                    if let value = LightConfigurationOnStartup(string: newValue) {
                                        var localCopy = filteredLightsConfiguration.wrappedValue
                                        for (index, _) in localCopy.enumerated() {
                                            localCopy[index].on.startupOn = value
                                        }
                                        
                                        filteredLightsConfiguration.wrappedValue = localCopy
                                    }
                                }
                            
                            Text("'bri':")
                            TextField("previous", text: $globalBri)
                                .onChange(of: globalBri) { previousValue, newValue in
                                    if let value = LightConfigurationBriStartup(string: newValue) {
                                        var localCopy = filteredLightsConfiguration.wrappedValue
                                        for (index, _) in localCopy.enumerated() {
                                            localCopy[index].bri.startupBri = value
                                        }
                                        
                                        filteredLightsConfiguration.wrappedValue = localCopy
                                    }
                                }
                        }
                        
                        GridRow {
                            Text("'ct':")
                            TextField("previous", text: $globalCt)
                                .onChange(of: globalCt) { previousValue, newValue in
                                    if let value = LightConfigurationCtStartup(string: newValue) {
                                        var localCopy = filteredLightsConfiguration.wrappedValue
                                        for (index, _) in localCopy.enumerated() {
                                            localCopy[index].color.startupCt = value
                                        }
                                        
                                        filteredLightsConfiguration.wrappedValue = localCopy
                                    }
                                }
                        }
                        
                        GridRow {
                            Text("'xy':")
                            TextField("previous", text: $globalXy)
                                .gridCellColumns(3)
                                .onChange(of: globalXy) { previousValue, newValue in
                                    if let value = LightConfigurationXyStartup(string: newValue) {
                                        var localCopy = filteredLightsConfiguration.wrappedValue
                                        for (index, _) in localCopy.enumerated() {
                                            localCopy[index].color.startupXy = value
                                        }
                                        
                                        filteredLightsConfiguration.wrappedValue = localCopy
                                    }
                                }
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 243)
                }
                
                VStack(alignment: .leading) {
                    Toggle(sources: filteredLightsExecuteIfOff, isOn: \.self) {
                        Text("Execute if 'off'")
                    }
                    
                    Toggle(sources: filteredLightsConfiguration, isOn: \.bri.coupleCt) {
                        Text("Couple 'ct' to 'bri'")
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.leading, 16)
            }
            .padding(.horizontal, 16)
            
            Text("Showing \(filteredLightsConfiguration.count) out of \(lightsConfiguration.count) lights")
            
            Divider()
            
            if isLoading {
                HStack {
                    Spacer()
                    
                    ProgressView()
                    
                    Spacer()
                }
                .frame(height: 300)
                .padding(.bottom, 8)
            } else if hasError {
                HStack {
                    Spacer()
                    
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .resizable()
                            .scaledToFit()
                            .symbolRenderingMode(.multicolor)
                            .frame(height: 32)
                        
                        Text("Error loading lights")
                            .foregroundStyle(.yellow)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                ScrollViewReader { scrollReader in
                    Table(filteredLightsConfiguration) {
                        TableColumn("Light") { $configuration in
                            ConfigurationView(light: $configuration)
                                .padding(.vertical, 4)
                        }
                        .width(240)
                        
                        TableColumn("Configuration") { $configuration in
                            ConfigurationEntriesView(light: $configuration)
                                .padding(.vertical, 4)
                        }
                        .width(240)
                        
                        TableColumn("Extras") { $configuration in
                            ConfigurationExtrasView(light: $configuration)
                                .padding(.vertical, 4)
                        }
                        .width(130)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .tableColumnHeaders(.hidden)
                    .tableStyle(.inset(alternatesRowBackgrounds: false))
                    // Size must be set explicitly
                    .frame(height: 300)
                    .scrollBounceBehavior(.basedOnSize)
                    .padding(.bottom, 8)
                }
            }
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .fixedSize()
                .keyboardShortcut(.cancelAction)
                
                Button("Apply Configuration") {
                    let lightsToConfigure = filteredLightsConfiguration.wrappedValue.filter({ $0.isEnabled })
                    
                    progressTotal = Double(lightsToConfigure.count)
                    isPresentingProgress = true
                    
                    Task {
                        try await self.configureLights(lightsToConfigure)
                        isPresentingProgress = false
                    } catch: { error in
                        isPresentingProgress = false
                        logger.error("\(error, privacy: .public)")
                        
                        window.handleError(error)
                    }
                }
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading || hasError)
            }
            .padding(.horizontal, 18)
        }
        .task {
            do {
                hasError = false
                window.clearWarnings()
                lightsConfiguration = try await RESTModel.shared.lightConfigurations()
            } catch {
                hasError = true
                
                logger.error("\(error, privacy: .public)")
                
                window.handleError(error)
            }
            
            isLoading = false
        }
        .sheet(isPresented: $isPresentingProgress) {
            ConfigurationProgressView(progressValue: $progressValue,
                                      progressTotal: $progressTotal,
                                      shouldCancel: $shouldCancel)
        }
    }
}

struct ConfigurationProgressView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var progressValue: Double
    @Binding var progressTotal: Double
    @Binding var shouldCancel: Bool
    
    var body: some View {
        VStack {
            ProgressView("", value: progressValue, total: progressTotal)
                .padding(.horizontal, 18)
            
            Text("Configured \(Int(progressValue)) out of ^[\(Int(progressTotal)) \("light")](inflect: true)")
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    shouldCancel = true
                    dismiss()
                }
                .fixedSize()
                .padding(.trailing, 18)
                .padding(.bottom, 12)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct ConfigurationView: View {
    // FIXME: Duplicated from LightItem model
    private func getImageName(modelId: String, lightName: String = "") -> String? {
        // Hue Fixture replacements
        if modelId.contains("LCG")
            && lightName.localizedCaseInsensitiveContains("fugato") {
            return "E00-C-57356"    // Hue Fugato Spots
        }
        
        // Hue Fixtures
        if modelId.contains("929002966") { return "E002-57346" }    // Hue Surimu Panel
        if modelId.contains("506313") { return "E00-C-57356" }      // Hue Fugato Spots
        
        // Hue Products and Bulbs
        if modelId.contains("LCG") { return "E027-57383" }  // GU10 bulbs
        if modelId.contains("LCL") { return "E06-A-57450" } // Hue Lightstrip plus
        if modelId.contains("LCT") { return "E015-57365" }  // E14 candle bulbs
        if modelId.contains("LCU") { return "E025-57381" }  // E14 luster bulbs
        if modelId.contains("LCA") { return "E028-57384" }  // A19 bulbs
        if modelId.contains("LOM") { return "E04-D-57421" } // Hue Smart Plug
        
        return nil
    }
    
    @Binding var light: LightConfiguration
    
    var body: some View {
        HStack {
            Toggle(isOn: $light.isEnabled) { }
            .toggleStyle(.checkbox)
            .padding(.trailing, 10)
            
            if let imageName = getImageName(modelId: light.modelId, lightName: light.name) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 24, maxHeight: 24)
            } else {
                Spacer()
                    .frame(width: 40, height: 24)
            }
            
            Text(light.name)
        }
        
        Spacer()
    }
}

struct ConfigurationEntriesView: View {
    @Binding var light: LightConfiguration
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var on: Binding<String> {
        Binding {
            switch light.on.startupOn {
            case .previous: return "previous"
            case .value(let value): return String(value)
            default: return ""
            }
        } set: { value in
            if let startup = LightConfigurationOnStartup(string: value) {
                light.on.startupOn = startup
            }
        }
    }
    
    private var bri: Binding<String> {
        Binding {
            switch light.bri.startupBri {
            case .previous: return "previous"
            case .value(let value): return String(value)
            default: return ""
            }
        } set: { value in
            if let startup = LightConfigurationBriStartup(string: value) {
                light.bri.startupBri = startup
            }
        }
    }
    
    private var ct: Binding<String> {
        Binding {
            switch light.color.startupCt {
            case .previous: return "previous"
            case .value(let value): return String(value)
            default: return ""
            }
        } set: { value in
            if let startup = LightConfigurationCtStartup(string: value) {
                light.color.startupCt = startup
            }
        }
    }
    
    private var xy: Binding<String> {
        Binding {
            switch light.color.startupXy {
            case .previous: return "previous"
            case .value(let value):
                let json = try? encoder.encode(value)
                if let json {
                    return String(data: json, encoding: .utf8)!.replacing(",", with: ", ")
                } else {
                    // FIXME: Error handling
                    logger.error("Value '\(value, privacy: .public)' is not valid for /config/color/xy/startup")
                    return ""
                }
            default: return ""
            }
        } set: { value in
            if let startup = LightConfigurationXyStartup(string: value) {
                light.color.startupXy = startup
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Grid(alignment: .leading) {
                GridRow {
                    Text("'on':")
                    TextField("previous", text: on)
                    
                    Text("'bri':")
                    TextField("previous", text: bri)
                }
                
                GridRow {
                    Text("'ct':")
                    TextField("previous", text: ct)
                }
                
                GridRow {
                    Text("'xy':")
                    TextField("previous", text: xy)
                    .gridCellColumns(3)
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }
}

struct ConfigurationExtrasView: View {
    @Binding var light: LightConfiguration
    
    private var executeIfOff: Binding<[Bool]> {
        Binding {
            return [light.bri.executeIfOff, light.color.executeIfOff]
        } set: { value in
            light.bri.executeIfOff = value[0]
            light.color.executeIfOff = value[0]
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Toggle(sources: executeIfOff, isOn: \.self) {
                Text("Execute if 'off'")
            }
            
            Toggle(isOn: $light.bri.coupleCt) {
                Text("Couple 'ct' to 'bri'")
            }
            
            Spacer()
        }
        .toggleStyle(.checkbox)
    }
}

//#Preview {
//    ConfigurationView(hueLights: .constant([
//        Light(lightId: 1, name: "Hue Light 1", state: LightState(), manufacturer: "Philips", modelId: "506313")
//    ]))
//}
