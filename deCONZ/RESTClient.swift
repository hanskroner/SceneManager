//
//  RESTClient.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import Foundation

// MARK: - REST API Returns

public enum APIError: Error {
    case apiError(context: APIErrorContext)
    case unknownResponse(data: Data?, response: URLResponse?)
}

extension APIError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .apiError(let context):
            return context.description
        case .unknownResponse(data: _, response: _):
            return "Unknown HTTP response from deCONZ REST API host"
        }
    }
}

public struct APIErrorContext: Decodable {
    let type: Int
    let address: String
    let description: String
    
    enum CodingKeys: String, CodingKey {
        case error
    }
    
    enum ErrorKeys: String, CodingKey {
        case type
        case address
        case description
    }
    
    public init(from decoder: Decoder) throws {
        let rootContainer = try decoder.container(keyedBy: CodingKeys.self)
        let errorContainer = try rootContainer.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error)
        type = try errorContainer.decode(Int.self, forKey: .type)
        address = try errorContainer.decode(String.self, forKey: .address)
        description = try errorContainer.decode(String.self, forKey: .description)
    }
}

public struct APISuccessContext: Decodable {
    let id: String
    
    enum CodingKeys: String, CodingKey {
        case success
    }
    
    enum SuccessKeys: String, CodingKey {
        case id
    }
    
    public init(from decoder: Decoder) throws {
        let rootContainer = try decoder.container(keyedBy: CodingKeys.self)
        let successContainer = try rootContainer.nestedContainer(keyedBy: SuccessKeys.self, forKey: .success)
        id = try successContainer.decode(String.self, forKey: .id)
    }
}

// MARK: - REST API

actor RESTClient {
    let apiKey: String
    let apiURL: String
    
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private enum RequestMethod: String {
        case delete = "DELETE"
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }
    
    public init(apiKey: String, apiURL: String) {
        self.apiKey = apiKey
        self.apiURL = apiURL
    }
    
    // MARK: - Internal Methods
    
    private func request(forPath path: String, using method: RequestMethod) -> URLRequest {
        var url = URLComponents(string: apiURL)!
        url.path = path
        
        var request = URLRequest(url: url.url!)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        return request
    }
    
    private func check(data: Data, from response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorResponse: [APIErrorContext] = try decoder.decode([APIErrorContext].self, from: data)
            guard let errorContext = errorResponse.first else { throw APIError.unknownResponse(data: data, response: response) }
            throw APIError.apiError(context: errorContext)
        }
    }
    
    // MARK: - deCONZ Lights REST API Methods
    
    func getAllLights() async throws -> [Int: RESTLight] {
        let path = "/api/\(self.apiKey)/lights/"
        let request = request(forPath: path, using: .get)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        return try decoder.decode([Int: RESTLight].self, from: data).filter { $0.value.type != "Configuration tool" }
    }
    
    func getLightState(lightID: Int) async throws -> RESTLightState {
        let path = "/api/\(self.apiKey)/lights/\(lightID)"
        let request = request(forPath: path, using: .get)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let light = try decoder.decode(RESTLight.self, from: data)
        return light.state
    }
    
    // MARK: - deCONZ Groups REST API Methods
    
    func createGroup(name: String) async throws -> Int {
        let group = RESTGroupObject(name: name)
        
        let path = "/api/\(self.apiKey)/groups/"
        var request = request(forPath: path, using: .post)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(group)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let successResponse: [APISuccessContext] = try decoder.decode([APISuccessContext].self, from: data)
        guard let successContext = successResponse.first,
              let responseId = Int(successContext.id)
        else { throw APIError.unknownResponse(data: data, response: response) }
        
        return responseId
    }
    
    func getAllGroups() async throws -> [Int: RESTGroup] {
        let path = "/api/\(self.apiKey)/groups/"
        let request = request(forPath: path, using: .get)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let groups = try decoder.decode([Int: RESTGroup].self, from: data)
        
        // Ignore Groups where `devicemembership` is not empty
        // These groups are created by switches or sensors.
        return groups.filter { $0.1.devicemembership.isEmpty }
    }

    func setGroupAttributes(groupId: Int, name: String? = nil, lights: [Int]? = nil) async throws {
        let group = RESTGroupObject(name: name, lights: lights?.map({ String($0) }))

        let path = "/api/\(self.apiKey)/groups/\(groupId)/"
        var request = request(forPath: path, using: .put)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(group)

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
    func setGroupState(groupId: Int, lightState: RESTLightState) async throws {
        let path = "/api/\(self.apiKey)/groups/\(groupId)/action"
        var request = request(forPath: path, using: .put)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(lightState)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }

    func deleteGroup(groupId: Int) async throws {
        let path = "/api/\(self.apiKey)/groups/\(groupId)/"
        let request = request(forPath: path, using: .delete)

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
    // MARK: - deCONZ Scenes REST API Methods
    
    func createScene(groupId: Int, name: String) async throws -> Int {
        let scene = RESTSceneObject(name: name)

        let path = "/api/\(self.apiKey)/groups/\(groupId)/scenes"
        var request = request(forPath: path, using: .post)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(scene)

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)

        let successResponse: [APISuccessContext] = try decoder.decode([APISuccessContext].self, from: data)
        guard let successContext = successResponse.first,
              let responseId = Int(successContext.id)
        else { throw APIError.unknownResponse(data: data, response: response) }

        return responseId
    }
    
    func getAllScenes() async throws -> [Int: [Int: RESTScene]] {
        let path = "/api/\(self.apiKey)/scenes/"
        let request = request(forPath: path, using: .get)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let groups = try decoder.decode([Int: RESTSceneGroup].self, from: data)
        
        return groups.reduce(into: [Int: [Int: RESTScene]](), { groupDictionary, groupEntry in
            groupDictionary[groupEntry.0] = groupEntry.1.scenes.reduce(into: [Int: RESTScene](), { sceneDictionary, sceneEntry in
                sceneDictionary[sceneEntry.0] = sceneEntry.1
            })
        })
    }
    
    func getSceneAttributes(groupID: Int, sceneID: Int) async throws -> RESTSceneAttributes? {
        // The deCONZ REST API is inconsistent in the way it handles xy Color Mode values.
        // When modifying a Scene that uses xy Color Mode, the values must be passed in as an array under
        // the "xy" JSON key. When getting the attributes of a Scene that uses xy Color Mode, the REST
        // API returns the values in separate "x" and "y" JSON keys.
        // To provide consisten and stable objects,'SceneLightState' is used to fetch the values from
        // the REST API and they are then re-packed into a 'RESTLightState'.
        struct SceneLightState: Decodable {
            let id: String?
            let bri: Int?
            let ct: Int?
            let hue: Int?
            let on: Bool?
            let sat: Int?
            let x: Double?
            let y: Double?
            let transitiontime: Int?
            
            let effect: String?
            let effect_duration: Int?
            let effect_speed: Double?
        }
        
        struct SceneLightStateContainer: Decodable {
            var dynamics: RESTDynamicState?
            var lights: [SceneLightState]
            var name: String
        }
        
        let path = "/api/\(self.apiKey)/groups/\(groupID)/scenes/\(sceneID)/"
        let request = request(forPath: path, using: .get)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let attrContainer: SceneLightStateContainer = try decoder.decode(SceneLightStateContainer.self, from: data)
        let restLightDict = attrContainer.lights.reduce(into: [Int: RESTLightState]()) { partialResult, sceneLightState in
            if let stringLightId = sceneLightState.id, let lightId = Int(stringLightId) {
                partialResult[lightId] = RESTLightState(bri: sceneLightState.bri,
                                                        ct: sceneLightState.ct,
                                                        effect: sceneLightState.effect,
                                                        hue: sceneLightState.hue,
                                                        on: sceneLightState.on,
                                                        sat: sceneLightState.sat,
                                                        xy: sceneLightState.x != nil && sceneLightState.y != nil ? [sceneLightState.x!, sceneLightState.y!] : nil,
                                                        transitiontime: sceneLightState.transitiontime,
                                                        effect_duration: sceneLightState.effect_duration,
                                                        effect_speed: sceneLightState.effect_speed)
            }
        }
        
        return RESTSceneAttributes(dynamics: attrContainer.dynamics, lights: restLightDict, name: attrContainer.name)
    }
    
    func setSceneAttributes(groupId: Int, sceneId: Int, name: String) async throws {
        let scene = RESTSceneObject(name: name)
        
        let path = "/api/\(self.apiKey)/groups/\(groupId)/scenes/\(sceneId)/"
        var request = request(forPath: path, using: .put)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(scene)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
    func modifyScene(groupId: Int, sceneId: Int, lightIds: [Int], lightState: RESTLightState?) async throws {
        // The deCONZ REST API is inconsistent in the way it handles xy Color Mode values.
        // When modifying a Scene that uses xy Color Mode, the values must be passed in as an array under
        // the "xy" JSON key. When getting the attributes of a Scene that uses xy Color Mode, the REST
        // API returns the values in separate "x" and "y" JSON keys.
        for (lightId) in lightIds {
            let path = "/api/\(self.apiKey)/groups/\(groupId)/scenes/\(sceneId)/lights/\(lightId)/state/"
            var request = request(forPath: path, using: .put)
            encoder.outputFormatting = []
            request.httpBody = try encoder.encode(lightState)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(data: data, from: response)
        }
    }
    
    func modifyHueScene(groupId: Int, sceneId: Int, lightIds: [Int], lightState: RESTLightState?) async throws {
        // An identical endpoint to to the one exposed by 'modifyScene' (different path).
        // For supported Philips Hue lights, this endpoint allows finer control over the attributes that
        // can be set in a scene. In addition to the attributes supported by 'modifyScene', 'modifyHueScene'
        // supports 'effect', 'effect_duration', and 'effect_speed'. All attributes are optional, allowing,
        // for example, the creation of scenes that only modify light's brightness - without affecting their
        // current color or state.
        for (lightId) in lightIds {
            // !!!: Trailing slash in path causes HTTP 431 response
            let path = "/api/\(self.apiKey)/hue-scenes/groups/\(groupId)/scenes/\(sceneId)/lights/\(lightId)/state"
            var request = request(forPath: path, using: .put)
            encoder.outputFormatting = []
            request.httpBody = try encoder.encode(lightState)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(data: data, from: response)
        }
    }
    
    func modifyHueDynamicScene(groupId: Int, sceneId: Int, dynamicState: RESTDynamicState?) async throws {
        // !!!: Trailing slash in path causes HTTP 431 response
        let path = "/api/\(self.apiKey)/hue-scenes/groups/\(groupId)/scenes/\(sceneId)/dynamic-state"
        var request = request(forPath: path, using: .put)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(dynamicState)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
    func recallScene(groupId: Int, sceneId: Int) async throws {
        let path = "/api/\(self.apiKey)/groups/\(groupId)/scenes/\(sceneId)/recall"
        let request = request(forPath: path, using: .put)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
//    func storeScene(groupID: Int, sceneID: Int) async throws {
//        let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes/\(sceneID)/store"
//        let request = request(forPath: path, using: .put)
//        
//        let (data, response) = try await URLSession.shared.data(for: request)
//        try check(data: data, from: response)
//    }
    
    func deleteScene(groupId: Int, sceneId: Int) async throws {
        let path = "/api/\(self.apiKey)/groups/\(groupId)/scenes/\(sceneId)/"
        let request = request(forPath: path, using: .delete)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
}
