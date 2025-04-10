//
//  Models.swift
//  deCONZ
//
//  Created by Hans Kröner on 23/10/2024.
//

import Foundation
import CryptoKit

private let uuidNamespace = "com.hanskroner.scenemanager"

extension UUID {
    public init?(namespace: String, input: String) {
        // Create a hash using SHA-1 - as per the UUID v5 spec
        // https://www.rfc-editor.org/rfc/rfc4122#section-4.3
        let hash = Insecure.SHA1.hash(data: Data((namespace + input).utf8))
        
        // Use the most-significant 128 bits of the hash set the fields
        // according to the spec. - they can be visualized easier here:
        // https://www.uuidtools.com/decode
        var truncatedHash = Array(hash.prefix(16))
        truncatedHash[6] &= 0x0F    // Clear version field
        truncatedHash[6] |= 0x50    // Set version to 5

        truncatedHash[8] &= 0x3F    // Clear variant field
        truncatedHash[8] |= 0x80    // Set variant to DCE 1.1
        
        // Compute the UUID
        guard let uuid = UUID(uuidString: NSUUID(uuidBytes: truncatedHash).uuidString) else { return nil }
        self = uuid
    }
}

// MARK: - Models

public protocol APIItem: Identifiable, Hashable, Equatable, Comparable {
    var id: UUID { get }
    var name: String { get set }
}

extension APIItem {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.name < rhs.name
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: Light State Model

@Observable
public final class LightState: Codable {
    public var alert: String?
    public var bri: Int?
    public var ct: Int?
    public var effect: String?
    public var on: Bool?
    public var xy: [Double]?
    
    public var transitiontime: Int?
    public var effect_duration: Int?
    public var effect_speed: Double?
    
    
    public init(alert: String? = nil,
         bri: Int? = nil,
         ct: Int? = nil,
         effect: String? = nil,
         on: Bool? = nil,
         xy: [Double]? = nil,
         transitiontime: Int? = nil,
         effect_duration: Int? = nil,
         effect_speed: Double? = nil) {
        self.alert = alert
        self.bri = bri
        self.ct = ct
        self.effect = effect
        self.on = on
        self.xy = xy
        self.transitiontime = transitiontime
        self.effect_duration = effect_duration
        self.effect_speed = effect_speed
    }
    
    enum CodingKeys: CodingKey {
        case alert, bri, ct, effect, on, xy, transitiontime, effect_duration, effect_speed
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.alert = try container.decodeIfPresent(String.self, forKey: .alert)
        self.bri = try container.decodeIfPresent(Int.self, forKey: .bri)
        self.ct = try container.decodeIfPresent(Int.self, forKey: .ct)
        self.effect = try container.decodeIfPresent(String.self, forKey: .effect)
        self.on = try container.decodeIfPresent(Bool.self, forKey: .on)
        self.xy = try container.decodeIfPresent([Double].self, forKey: .xy)
        self.transitiontime = try container.decodeIfPresent(Int.self, forKey: .transitiontime)
        self.effect_duration = try container.decodeIfPresent(Int.self, forKey: .effect_duration)
        self.effect_speed = try container.decodeIfPresent(Double.self, forKey: .effect_speed)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(self.alert, forKey: .alert)
        try container.encodeIfPresent(self.bri, forKey: .bri)
        try container.encodeIfPresent(self.ct, forKey: .ct)
        try container.encodeIfPresent(self.effect, forKey: .effect)
        try container.encodeIfPresent(self.on, forKey: .on)
        try container.encodeIfPresent(self.xy, forKey: .xy)
        try container.encodeIfPresent(self.transitiontime, forKey: .transitiontime)
        try container.encodeIfPresent(self.effect_duration, forKey: .effect_duration)
        try container.encodeIfPresent(self.effect_speed, forKey: .effect_speed)
    }
    
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()
    
    public var description: String {
        let jsonData = try! jsonEncoder.encode(self)
        let jsonObject = try! jsonDecoder.decode(JSON.self, from: jsonData)
        
        return jsonObject.description
    }
    
    public var json: String {
        let jsonData = try! jsonEncoder.encode(self)
        let jsonObject = try! jsonDecoder.decode(JSON.self, from: jsonData)
        
        return jsonObject.prettyPrint()
    }
}

// MARK: Light Model

@Observable
public final class Light: APIItem, Codable {
    public let id: UUID
    public var name: String
    
    public let lightId: Int
    public var state: LightState
    
    public let manufacturer: String
    public let modelId: String
    
    init(lightId: Int, name: String, state: LightState = LightState(), manufacturer: String, modelId: String) {
        self.id = UUID(namespace: uuidNamespace, input: "\(lightId)")!
        self.name = name
        
        self.lightId = lightId
        self.state = state
        
        self.manufacturer = manufacturer
        self.modelId = modelId
    }
    
    enum CodingKeys: CodingKey {
        case light_id, name, state, manufacturer, model_id
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        lightId = try container.decode(Int.self, forKey: .light_id)
        state = try container.decode(LightState.self, forKey: .state)
        
        manufacturer = try container.decode(String.self, forKey: .manufacturer)
        modelId = try container.decode(String.self, forKey: .model_id)
        
        id = UUID(namespace: uuidNamespace, input: "\(lightId)")!
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(lightId, forKey: .light_id)
        try container.encode(name, forKey: .name)
        try container.encode(state, forKey: .state)
        
        try container.encode(manufacturer, forKey: .manufacturer)
        try container.encode(modelId, forKey: .model_id)
    }
}

// MARK: Group Model

@Observable
public final class Group: APIItem, Codable {
    public let id: UUID
    public var name: String
    
    public let groupId: Int
    public var lightIds: [Int]
    public var sceneIds: [Int]
    
    public init(groupId: Int, name: String, lightIds: [Int] = [], sceneIds: [Int] = []) {
        self.id = UUID(namespace: uuidNamespace, input: "\(groupId)")!
        self.name = name
        
        self.groupId = groupId
        self.lightIds = lightIds
        self.sceneIds = sceneIds
    }
    
    enum CodingKeys: CodingKey {
        case group_id, name, light_ids, scene_ids
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        groupId = try container.decode(Int.self, forKey: .group_id)
        lightIds = try container.decodeIfPresent([Int].self, forKey: .light_ids) ?? []
        sceneIds = try container.decodeIfPresent([Int].self, forKey: .scene_ids) ?? []
        
        self.id = UUID(namespace: uuidNamespace, input: "\(groupId)")!
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(groupId, forKey: .group_id)
        try container.encode(name, forKey: .name)
        try container.encode(lightIds, forKey: .light_ids)
        try container.encode(sceneIds, forKey: .scene_ids)
    }
}

// MARK: Scene Model

@Observable
public final class Scene: APIItem, Codable {
    public let id: UUID
    public var name: String
    
    public let groupId: Int
    public let sceneId: Int
    public var lightIds: [Int]
    public var lightStates: [Int: LightState]
    public var dynamicState: DynamicState?
    
    public init(sceneId: Int, groupId: Int, name: String, lightIds: [Int] = [], lightStates: [Int: LightState] = [:], dynamicState: DynamicState? = nil) {
        self.id = UUID(namespace: uuidNamespace, input: "\(groupId)-\(sceneId)")!
        self.name = name
        
        self.sceneId = sceneId
        self.groupId = groupId
        self.lightIds = lightIds
        self.lightStates = lightStates
        self.dynamicState = dynamicState
    }
    
    enum CodingKeys: CodingKey {
        case scene_id, group_id, name, light_ids, scene_ids, light_states, dynamic_state
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        sceneId = try container.decode(Int.self, forKey: .scene_id)
        groupId = try container.decodeIfPresent(Int.self, forKey: .scene_id) ?? 0
        lightIds = try container.decodeIfPresent([Int].self, forKey: .light_ids) ?? []
        lightStates = try container.decodeIfPresent([Int: LightState].self, forKey: .light_states) ?? [:]
        dynamicState = try container.decodeIfPresent(DynamicState.self, forKey: .dynamic_state)
        
        self.id = UUID(namespace: uuidNamespace, input: "\(groupId)-\(sceneId)")!
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(sceneId, forKey: .scene_id)
        try container.encode(groupId, forKey: .group_id)
        try container.encode(name, forKey: .name)
        try container.encode(lightIds, forKey: .light_ids)
        try container.encode(lightStates, forKey: .light_states)
        try container.encodeIfPresent(dynamicState, forKey: .dynamic_state)
    }
}

// MARK: - Dynamic Scene Model

public enum DynamicStateApplication: String, Codable {
    case ignore
    case sequence
    case random
}

public final class DynamicStateEffect: Codable {
    public var effect: String
    
    public var xy: [Double]?
    public var ct: Int?
    
    public var effect_speed: Double?
}

public final class DynamicState: Codable {
    public var bri: Int?
    public var xy: [[Double]]?
    public var ct: Int?
    public var transitiontime: Int?
    
    let effects: [DynamicStateEffect]?
    
    public var effect_speed: Double
    public var auto_dynamic: Bool
    public var scene_apply: DynamicStateApplication?
    
    public init(bri: Int? = nil, xy: [[Double]]? = nil, ct: Int? = nil, transitiontime: Int? = nil, effects: [DynamicStateEffect]? = nil, effect_speed: Double, auto_dynamic: Bool, scene_apply: DynamicStateApplication? = nil) {
        self.bri = bri
        self.xy = xy
        self.ct = ct
        self.transitiontime = transitiontime
        
        self.effects = effects
        
        self.effect_speed = effect_speed
        self.auto_dynamic = auto_dynamic
        self.scene_apply = scene_apply
    }
}
