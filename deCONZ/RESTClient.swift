//
//  RESTClient.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import Foundation

// MARK: - REST API Returns

public enum APIError: Error {
    case apiError(context: [APIResponseContextError])
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

// MARK: - REST API Response Context

public enum APIResponseContext: Decodable {
    case error(APIResponseContextError)
    case success(APIResponseContextSuccess)
    
    enum CodingKeys: CodingKey {
        case error, success
    }
    
    public init(from decoder: Decoder) throws {
        let rootContainer = try! decoder.container(keyedBy: CodingKeys.self)

        if let successContainer = try? rootContainer.decodeIfPresent(APIResponseContextSuccess.self, forKey: .success) {
            self = .success(successContainer)
        } else if let errorContainer = try? rootContainer.decodeIfPresent(APIResponseContextError.self, forKey: .error) {
            self = .error(errorContainer)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath,
                                                                    debugDescription: "Not a 'success' or 'error' response"))
        }
    }
}

public struct APIResponseContextError: Decodable, Sendable {
    public let type: Int
    public let address: String
    public let description: String
}

public struct APIResponseContextSuccess: Decodable {
    let path: String
    let value: Any
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let entries = try container.decode(JSON.self).objectValue {
            path = entries.keys.first ?? ""
            
            if let string = entries.values.first?.stringValue {
                value = string
            } else if let double = entries.values.first?.doubleValue {
                value = double
            } else if let boolean = entries.values.first?.boolValue {
                value = boolean
            } else {
                value = ""
            }
        } else {
            path = ""
            value = ""
        }
    }
}

// MARK: - REST API

actor RESTClient {
    let apiKey: String
    let apiURL: String
    
    private var activity: RESTActivity?
    
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private enum RequestMethod: String {
        case delete = "DELETE"
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }
    
    public init(apiKey: String, apiURL: String) {
        encoder.outputFormatting = []
        
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
        var errorEntries: [APIResponseContextError] = []
        
        do {
            let responseEntries: [APIResponseContext] = try decoder.decode([APIResponseContext].self, from: data)
            for entry in responseEntries {
                switch entry {
                case .success(_): break
                case .error(let error): errorEntries.append(error)
                }
            }
        } catch {
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw APIError.unknownResponse(data: data, response: response)
            }
        }
        
        // Collect all the error entries and throw an APIError
        if errorEntries.count > 0 {
            throw APIError.apiError(context: errorEntries)
        }
    }

    // MARK: - Isolated Methods
    
    func setActivity(_ activity: RESTActivity?) {
        self.activity = activity
    }
    
    // MARK: - deCONZ Configuration REST API Methods
    
    func getFullState() async throws -> RESTConfiguration {
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/config/")
        
        do {
            let request = request(forPath: activity.path, using: .get)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            let configuration = try decoder.decode(RESTConfiguration.self, from: data)
            
            self.activity?.append(activity)
            return configuration
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func acquireAPIKey(name: String? = nil, key: String? = nil) async throws -> String {
        // Generate a name with the format "SceneManager#xxxxxxxx" if one
        // isn't provided. Confusingly, the REST API calls the key "username" and
        // the identifier name for the key "devicetype" in this API call.
        let hexDate = String(abs(Date().hashValue), radix: 16, uppercase: false)
        let config = RESTAPIKeyObject(devicetype: name ?? String("SceneManager#"+hexDate.prefix(8)), username: key)
        
        var activity = RESTActivityEntry(path: "/api")
        
        do {
            var request = request(forPath: activity.path, using: .post)
            request.httpBody = try encoder.encode(config)
            activity.request = String(data: request.httpBody!, encoding: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            let successResponse: [APIResponseContext] = try decoder.decode([APIResponseContext].self, from: data)
            let username: String? = {
                switch successResponse.first {
                case .success(let success):
                    guard success.path == "username", let username = success.value as? String else { return nil }
                    return username
                    
                default: return nil
                }
            }()
            
            guard let username else { throw APIError.unknownResponse(data: data, response: response) }
            self.activity?.append(activity)
            return username
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func deleteAPIKey(key: String) async throws {
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/config/whitelist/\(key)")
        
        do {
            let request = request(forPath: activity.path, using: .delete)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            self.activity?.append(activity)
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    // MARK: - deCONZ Lights REST API Methods
    
    func getAllLights() async throws -> [Int: RESTLight] {
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/lights/")
        
        do {
            let request = request(forPath: activity.path, using: .get)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            let allLights = try decoder.decode([Int: RESTLight].self, from: data).filter { $0.value.type != "Configuration tool" }
            
            self.activity?.append(activity)
            return allLights
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func getLightState(lightId: Int) async throws -> RESTLightState {
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/lights/\(lightId)")
        
        do {
            let request = request(forPath: activity.path, using: .get)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            let light = try decoder.decode(RESTLight.self, from: data)
            
            self.activity?.append(activity)
            return light.state
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func setLightAttributes(lightId: Int, name: String? = nil) async throws {
        let light = RESTLightObject(name: name)

        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/lights/\(lightId)/")

        do {
            var request = request(forPath: activity.path, using: .put)
            request.httpBody = try encoder.encode(light)
            activity.request = String(data: request.httpBody!, encoding: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            self.activity?.append(activity)
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func setLightConfiguration(lightId: Int, configuration: RESTLightConfiguration) async throws {
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/lights/\(lightId)/config")
        
        do {
            var request = request(forPath: activity.path, using: .put)
            request.httpBody = try encoder.encode(configuration)
            activity.request = String(data: request.httpBody!, encoding: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            self.activity?.append(activity)
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    // MARK: - deCONZ Groups REST API Methods
    
    func createGroup(name: String) async throws -> Int {
        let group = RESTGroupObject(name: name)
        
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/groups/")
        
        do {
            var request = request(forPath: activity.path, using: .post)
            request.httpBody = try encoder.encode(group)
            activity.request = String(data: request.httpBody!, encoding: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            let successResponse: [APIResponseContext] = try decoder.decode([APIResponseContext].self, from: data)
            let responseId: Int? = {
                switch successResponse.first {
                case .success(let success):
                    // The REST API returns "id" as a String
                    guard success.path == "id", let id = success.value as? String else { return nil }
                    return Int(id)
                    
                default: return nil
                }
            }()
            
            guard let responseId else { throw APIError.unknownResponse(data: data, response: response) }
            self.activity?.append(activity)
            return responseId
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func getAllGroups() async throws -> [Int: RESTGroup] {
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/groups/")
        
        do {
            let request = request(forPath: activity.path, using: .get)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            let groups = try decoder.decode([Int: RESTGroup].self, from: data)
            
            // Ignore Groups where `devicemembership` is not empty
            // These groups are created by switches or sensors.
            self.activity?.append(activity)
            return groups.filter { $0.1.devicemembership.isEmpty }
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }

    func setGroupAttributes(groupId: Int, name: String? = nil, lights: [Int]? = nil) async throws {
        let group = RESTGroupObject(name: name, lights: lights?.map({ String($0) }))

        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/groups/\(groupId)/")

        do {
            var request = request(forPath: activity.path, using: .put)
            request.httpBody = try encoder.encode(group)
            activity.request = String(data: request.httpBody!, encoding: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            self.activity?.append(activity)
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func setGroupState(groupId: Int, lightState: RESTLightState) async throws {
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/groups/\(groupId)/action")
        
        do {
            var request = request(forPath: activity.path, using: .put)
            request.httpBody = try encoder.encode(lightState)
            activity.request = String(data: request.httpBody!, encoding: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            self.activity?.append(activity)
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }

    func deleteGroup(groupId: Int) async throws {
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/groups/\(groupId)/")
        
        do {
            let request = request(forPath: activity.path, using: .delete)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            self.activity?.append(activity)
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    // MARK: - deCONZ Scenes REST API Methods
    
    func createScene(groupId: Int, name: String) async throws -> Int {
        let scene = RESTSceneObject(name: name)
        
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/groups/\(groupId)/scenes")

        do {
            var request = request(forPath: activity.path, using: .post)
            request.httpBody = try encoder.encode(scene)
            activity.request = String(data: request.httpBody!, encoding: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            let successResponse: [APIResponseContext] = try decoder.decode([APIResponseContext].self, from: data)
            let responseId: Int? = {
                switch successResponse.first {
                case .success(let success):
                    // The REST API returns "id" as a String
                    guard success.path == "id", let id = success.value as? String else { return nil }
                    return Int(id)
                    
                default: return nil
                }
            }()
            
            guard let responseId else { throw APIError.unknownResponse(data: data, response: response) }
            
            self.activity?.append(activity)
            return responseId
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func getAllScenes() async throws -> [Int: [Int: RESTScene]] {
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/scenes/")
        
        do {
            let request = request(forPath: activity.path, using: .get)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            let groups = try decoder.decode([Int: RESTSceneGroup].self, from: data)
            
            self.activity?.append(activity)
            return groups.reduce(into: [Int: [Int: RESTScene]](), { groupDictionary, groupEntry in
                groupDictionary[groupEntry.0] = groupEntry.1.scenes.reduce(into: [Int: RESTScene](), { sceneDictionary, sceneEntry in
                    sceneDictionary[sceneEntry.0] = sceneEntry.1
                })
            })
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func getSceneAttributes(groupId: Int, sceneId: Int) async throws -> RESTSceneAttributes? {
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
        
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/groups/\(groupId)/scenes/\(sceneId)/")
        
        do {
            let request = request(forPath: activity.path, using: .get)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
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
            
            self.activity?.append(activity)
            return RESTSceneAttributes(dynamics: attrContainer.dynamics, lights: restLightDict, name: attrContainer.name)
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func setSceneAttributes(groupId: Int, sceneId: Int, name: String) async throws {
        let scene = RESTSceneObject(name: name)
        
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/groups/\(groupId)/scenes/\(sceneId)/")
        
        do {
            var request = request(forPath: activity.path, using: .put)
            request.httpBody = try encoder.encode(scene)
            activity.request = String(data: request.httpBody!, encoding: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            self.activity?.append(activity)
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func modifyScene(groupId: Int, sceneId: Int, lightIds: [Int], lightState: RESTLightState?) async throws {
        // The deCONZ REST API is inconsistent in the way it handles xy Color Mode values.
        // When modifying a Scene that uses xy Color Mode, the values must be passed in as an array under
        // the "xy" JSON key. When getting the attributes of a Scene that uses xy Color Mode, the REST
        // API returns the values in separate "x" and "y" JSON keys.
        for (lightId) in lightIds {
            var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/groups/\(groupId)/scenes/\(sceneId)/lights/\(lightId)/state/")
            
            do {
                var request = request(forPath: activity.path, using: .put)
                request.httpBody = try encoder.encode(lightState)
                activity.request = String(data: request.httpBody!, encoding: .utf8)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                activity.response = String(data: data, encoding: .utf8)
                
                try check(data: data, from: response)
                
                self.activity?.append(activity)
            } catch {
                activity.outcome = .failure(description: error.localizedDescription)
                self.activity?.append(activity)
                
                throw error
            }
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
            var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/hue-scenes/groups/\(groupId)/scenes/\(sceneId)/lights/\(lightId)/state")
            
            do {
                var request = request(forPath: activity.path, using: .put)
                request.httpBody = try encoder.encode(lightState)
                activity.request = String(data: request.httpBody!, encoding: .utf8)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                activity.response = String(data: data, encoding: .utf8)
                
                try check(data: data, from: response)
                
                self.activity?.append(activity)
            } catch {
                activity.outcome = .failure(description: error.localizedDescription)
                self.activity?.append(activity)
                
                throw error
            }
        }
    }
    
    func modifyHueDynamicScene(groupId: Int, sceneId: Int, dynamicState: RESTDynamicState?) async throws {
        // !!!: Trailing slash in path causes HTTP 431 response
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/hue-scenes/groups/\(groupId)/scenes/\(sceneId)/dynamic-state")
        
        do {
            var request = request(forPath: activity.path, using: .put)
            request.httpBody = try encoder.encode(dynamicState)
            activity.request = String(data: request.httpBody!, encoding: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            self.activity?.append(activity)
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func recallScene(groupId: Int, sceneId: Int) async throws {
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/groups/\(groupId)/scenes/\(sceneId)/recall")
        
        do {
            let request = request(forPath: activity.path, using: .put)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            self.activity?.append(activity)
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
    
    func deleteScene(groupId: Int, sceneId: Int) async throws {
        var activity = RESTActivityEntry(path: "/api/\(self.apiKey)/groups/\(groupId)/scenes/\(sceneId)/")
        
        do {
            let request = request(forPath: activity.path, using: .delete)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            activity.response = String(data: data, encoding: .utf8)
            
            try check(data: data, from: response)
            
            self.activity?.append(activity)
        } catch {
            activity.outcome = .failure(description: error.localizedDescription)
            self.activity?.append(activity)
            
            throw error
        }
    }
}
