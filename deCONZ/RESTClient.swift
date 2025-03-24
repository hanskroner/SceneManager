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
        
        return try decoder.decode([Int: RESTLight].self, from: data)
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

    func deleteGroup(groupId: Int) async throws {
        let path = "/api/\(self.apiKey)/groups/\(groupId)/"
        let request = request(forPath: path, using: .delete)

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
//    public func getAllGroups() async throws -> ([Int: Group], [Int: [Int: Scene]]) {
//        let path = "/api/\(self.apiKey)/groups/"
//        let request = request(forPath: path, using: .get)
//        
//        let (data, response) = try await URLSession.shared.data(for: request)
//        try check(data: data, from: response)
//        
//        // The response from the REST API bundles Scene information into the Group information. It avoids
//        // the need to make two separate requests to obtain the information, but ever so slightly ruins
//        // the consistency of the data structures used to hold the information, where Groups now hold
//        // the names of their Scenes, but not the names of their Lights.
//        //
//        // The code below separates Group and Scene information into their own containers, which are then
//        // returned by the function as a tuple. The Group information retains only the IDs of its Scenes,
//        // which is the same information it holds on its Lights. The Scene information is put in its own
//        // object, indexed by the Group they belong to.
//        
//        let apiResponse = try decoder.decode([Int: RESTGroup].self, from: data)
//        
//        let groupsTuple = apiResponse.map { ($0.0, Group(from: $0.1, id: $0.0)) }
//        let groups = Dictionary(uniqueKeysWithValues: groupsTuple)
//
//        let scenesTuple = apiResponse.map { (groupId, group) in
//            (groupId,
//             group.scenes.reduce(into: [Int: Scene]()) {
//                let scene = Scene(from: $1, sceneId: Int($1.id)!, groupId: groupId)
//                $0[scene.sceneId] = scene
//            })
//        }
//        let scenes = Dictionary(uniqueKeysWithValues: scenesTuple)
//        
//        return (groups, scenes)
//    }
    
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
    
    func getSceneState(lightId: Int, groupID: Int, sceneID: Int) async throws -> RESTLightState? {
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
        }
        struct SceneLightStateContainer: Decodable {
            var lights: [SceneLightState]
        }
        
        let path = "/api/\(self.apiKey)/groups/\(groupID)/scenes/\(sceneID)/"
        let request = request(forPath: path, using: .get)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let tempLightStates: SceneLightStateContainer = try decoder.decode(SceneLightStateContainer.self, from: data)
        
        for (restLightState) in tempLightStates.lights {
            if let stringLightId = restLightState.id,
               lightId == Int(stringLightId) {
                return RESTLightState(alert: nil,
                                      bri: restLightState.bri,
                                      colormode: nil,
                                      ct: restLightState.ct,
                                      effect: nil,
                                      hue: restLightState.hue,
                                      on: restLightState.on,
                                      reachable: nil,
                                      sat: restLightState.sat,
                                      xy: restLightState.x != nil && restLightState.y != nil ? [restLightState.x!, restLightState.y!] : nil,
                                      transitiontime: restLightState.transitiontime,
                                      effect_duration: nil,
                                      effect_speed: nil)
            }
        }
        
        return nil
    }
    
//    func getSceneAttributes(groupID: Int, sceneID: Int) async throws -> [Int: deCONZLightState] {
//        struct LightStateContainer: Decodable {
//            var lights: [deCONZLightStateRESTParameter]
//        }
//        
//        let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes/\(sceneID)/"
//        let request = request(forPath: path, using: .get)
//        
//        let (data, response) = try await URLSession.shared.data(for: request)
//        try check(data: data, from: response)
//        
//        let tempLightStates: LightStateContainer = try decoder.decode(LightStateContainer.self, from: data)
//        
//        var lightStates = [Int: deCONZLightState]()
//        
//        for (restLightState) in tempLightStates.lights {
//            if let stringLightID = restLightState.id,
//               let lightID = Int(stringLightID) {
//                lightStates[lightID] = deconzLightState(from: restLightState)
//            }
//        }
//        
//        return lightStates
//    }
    
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
        // Build the request body by decoding and re-encoding 'state' to JSON (to 'validate' it).
        // Since 'state' is the same for all passed-in lights, this only needs to be done once.
        // Note that the deCONZ REST API is inconsistent in the way it handles xy Color Mode values.
        // When modifying a Scene that uses xy Color Mode, the values must be passed in as an array under
        // the "xy" JSON key. When getting the attributes of a Scene that uses xy Color Mode, the REST
        // API returns the values in separate "x" and "y" JSON keys.
        
        // Note that 'deconzLightStateRESTParameter' sets 'id' to nil and only returns 'xy'
        // colormode as an Array of Doubles.
//        let restLightState = deconzLightStateRESTParameter(from: state)
        
        for (lightId) in lightIds {
            let path = "/api/\(self.apiKey)/groups/\(groupId)/scenes/\(sceneId)/lights/\(lightId)/state/"
            var request = request(forPath: path, using: .put)
            encoder.outputFormatting = []
            request.httpBody = try encoder.encode(lightState)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(data: data, from: response)
        }
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
