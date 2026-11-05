//
//  CopyLightConfiguration.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2026.
//

import SwiftUI
import OSLog
import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "copy-light")

struct CopyLightConfigurationView: View {
    @Environment(WindowItem.self) private var window
    
    @Environment(\.dismiss) private var dismiss
    
    // deCONZ gets no feedback from the Zigbee network on whether a command
    // has been processed, so commands are spaced out by a configurable delay.
    @AppStorage("copy_light_delay_ms") private var delay: Int = 300
    
    // Each picker gets its own 'Lights' model so selections are independent
    @State private var sourceLights = Lights()
    @State private var destinationLights = Lights()
    @State private var allLightItems: [LightItem] = []
    
    @State private var plan: LightCopyPlan? = nil
    @State private var isLoadingPlan = false
    @State private var isPresentingConfirmation = false
    
    // Progress reporting
    @State private var isPresentingProgress = false
    @State private var progressValue = 0.0
    @State private var progressTotal = 100.0
    @State private var shouldCancel = false
    
    private var sourceLightItem: LightItem? {
        sourceLights.selectedLightItems.first
    }
    
    private var destinationLightItem: LightItem? {
        destinationLights.selectedLightItems.first
    }
    
    // Each list excludes the light selected in the other one
    private func updateLightItems() {
        sourceLights.items = allLightItems.filter { $0.id != destinationLightItem?.id }
        destinationLights.items = allLightItems.filter { $0.id != sourceLightItem?.id }
    }
    
    private func copyLight(using plan: LightCopyPlan) async throws {
        shouldCancel = false
        progressValue = 0
        
        for (index, step) in plan.steps.enumerated() {
            guard !shouldCancel else { return }
            
            do {
                logger.info("\(step.description, privacy: .public)")
                try await RESTModel.shared.executeLightCopyStep(step, in: plan)
            } catch {
                shouldCancel = true
                throw error
            }
            
            progressValue = Double(index + 1)
            
            if index < plan.steps.count - 1 {
                try await Task.sleep(for: .milliseconds(delay))
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Copy Light Configuration")
                .font(.headline)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Source")
                        .foregroundStyle(.secondary)
                    
                    LightView(style: .picker)
                        .environment(sourceLights)
                }
                
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading) {
                    Text("Destination")
                        .foregroundStyle(.secondary)
                    
                    LightView(style: .picker)
                        .environment(destinationLights)
                }
            }
            .frame(height: 300)
            
            HStack {
                Text("Delay between commands:")
                
                TextField("", value: $delay, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                
                Stepper("", value: $delay, in: 0...5000, step: 50)
                    .labelsHidden()
                
                Text("ms")
            }
            
            Label {
                if let sourceLightItem, let destinationLightItem {
                    Text("'\(destinationLightItem.name)' will be removed from all of its current groups and scenes, and then added to the same groups and scenes as '\(sourceLightItem.name)' with identical values. This cannot be undone.")
                } else {
                    Text("The destination light will be removed from all of its current groups and scenes, and then added to the same groups and scenes as the source light with identical values. This cannot be undone.")
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
            .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                if isLoadingPlan {
                    ProgressView()
                        .controlSize(.small)
                } else if let plan {
                    Text("Removes from ^[\(plan.removedSceneCount) scene](inflect: true) and ^[\(plan.removedGroupCount) group](inflect: true). Adds to ^[\(plan.addedGroupCount) group](inflect: true) and ^[\(plan.addedSceneCount) scene](inflect: true).")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Select a source and a destination light.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 20)
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .fixedSize()
                .keyboardShortcut(.cancelAction)
                
                Button("Copy Configuration") {
                    isPresentingConfirmation = true
                }
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .disabled(plan == nil || isLoadingPlan)
            }
        }
        .padding(.horizontal, 6)
        .task {
            allLightItems = RESTModel.shared.lights
                .map { LightItem(light: $0) }
                .sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            updateLightItems()
        }
        .onChange(of: sourceLights.selectedLightItemIds) {
            updateLightItems()
        }
        .onChange(of: destinationLights.selectedLightItemIds) {
            updateLightItems()
        }
        .task(id: [sourceLightItem?.lightId, destinationLightItem?.lightId]) {
            plan = nil
            guard let sourceLightItem, let destinationLightItem else { return }
            
            isLoadingPlan = true
            defer { isLoadingPlan = false }
            
            do {
                window.clearWarnings()
                plan = try await RESTModel.shared.lightCopyPlan(fromLightId: sourceLightItem.lightId,
                                                                toLightId: destinationLightItem.lightId)
            } catch {
                logger.error("\(error, privacy: .public)")
                
                window.handleError(error)
            }
        }
        .confirmationDialog("Replace the configuration of '\(destinationLightItem?.name ?? "")'?",
                            isPresented: $isPresentingConfirmation) {
            Button("Copy Configuration", role: .destructive) {
                guard let plan else { return }
                
                progressTotal = Double(plan.steps.count)
                isPresentingProgress = true
                
                window.clearWarnings()
                Task {
                    do {
                        try await copyLight(using: plan)
                        isPresentingProgress = false
                        
                        if !shouldCancel {
                            dismiss()
                        }
                    } catch {
                        isPresentingProgress = false
                        logger.error("\(error, privacy: .public)")
                        
                        window.handleError(error)
                    }
                }
            }
        } message: {
            Text("This will send ^[\(plan?.steps.count ?? 0) command](inflect: true) to the gateway.")
        }
        .sheet(isPresented: $isPresentingProgress) {
            ConfigurationProgressView(progressValue: $progressValue,
                                      progressTotal: $progressTotal,
                                      shouldCancel: $shouldCancel,
                                      noun: "step")
        }
    }
}
