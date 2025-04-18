//
//  LightModel.swift
//  SceneManager
//
//  Created by Hans Kröner on 17/04/2025.
//

import SwiftUI
import OSLog

import deCONZ

private let logger = Logger(subsystem: "com.hanskroner.scenemanager", category: "models-light")
private let uuidNamespace = "com.hanskroner.scenemanager.light"

// MARK: - Lights Model

@Observable
class Lights {
    var items: [LightItem] = []
    var selectedLightItemIds = Set<UUID>()
    
    // FIXME: Remove init for proper data feed from a Model
    convenience init(useDemoData: Bool) {
        self.init()
        
        let contentURL = Bundle.main.url(forResource: "Lights", withExtension: "json")
        let contentData = try! Data(contentsOf: contentURL!)
        let decoder = JSONDecoder()
        
        do {
            self.items = try decoder.decode([LightItem].self, from: contentData)
            
            // Sort the items
            self.items.sort(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        } catch {
            logger.error("\(error, privacy: .public)")
        }
    }
    
    func lightItem(for id: UUID) -> LightItem? {
        return items.first(where: { $0.id == id })
    }
    
    var selectedLightItems: Set<LightItem> {
        // Find the selected LighItems
        // The lists are traversed in this particular way to preseve the selection ordering.
        var lightItems = Set<LightItem>()
        selectedLoop: for (selectedLightItemID) in selectedLightItemIds {
            existingLoop: for (lightItem) in self.items {
                if (lightItem.id == selectedLightItemID) {
                    lightItems.insert(lightItem)
                    continue selectedLoop
                }
            }
        }
        
        return lightItems
    }
}

// MARK: - LightItem Model

@Observable
class LightItem: Identifiable, Codable, Hashable {
    static func == (lhs: LightItem, rhs: LightItem) -> Bool {
        return lhs.id == rhs.id
            && lhs._fetched == rhs._fetched
    }
    
    // TODO: Account for more bulb and product models
    // 'lighName' is provided for situations where the bulb originally included with a
    // fixture is replaced and its identifiers no longer match a fixture - just a bulb.
    // The light name is used as an additional differentiator.
    private static func getImageName(modelId: String, lightName: String = "") -> String? {
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
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let id: UUID
    
    let lightId: Int
    let name: String
    
    let imageName: String?
    
    // Set when the SidebarItem is created.
    // It's used in the Equatable extension to nudge SwiftUI into thiking two
    // SidebarItems with identical UUIDs are actually different and to decide
    // to redraw Views that depend on this SidebarItem.
    private let _fetched: Date
    
    
    enum CodingKeys: CodingKey {
        case light_id, name, image_name
    }
    
    init(lightId: Int, name: String, imageName: String? = nil) {
        self.id = UUID(namespace: uuidNamespace, input: "\(lightId)")!
        self.lightId = lightId
        self.name = name
        self.imageName = imageName
        
        self._fetched = Date()
    }
    
    convenience init(light: Light) {
        self.init(lightId: light.lightId,
                  name: light.name,
                  imageName: Self.getImageName(modelId: light.modelId,
                                               lightName: light.name))
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        lightId = try container.decode(Int.self, forKey: .light_id)
        name = try container.decode(String.self, forKey: .name)
        imageName = try container.decodeIfPresent(String.self, forKey: .image_name)
        
        id = UUID(namespace: uuidNamespace, input: "\(lightId)")!
        self._fetched = Date()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(lightId, forKey: .light_id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(imageName, forKey: .image_name)
    }
}
