//
//  deCONZClient.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import Foundation

import Foundation

actor deCONZClient: ObservableObject {
    private var keyAPI: String {
        return UserDefaults.standard.string(forKey: "deconz_key") ?? ""
    }
    
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private enum RequestMethod: String {
        case delete = "DELETE"
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }
    
    // MARK: - Internal Methods
    
    private func request(forPath path: String, using method: RequestMethod) -> URLRequest {
        var url = URLComponents(string: UserDefaults.standard.string(forKey: "deconz_url") ?? "")!
        url.path = path
        
        var request = URLRequest(url: url.url!)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        return request
    }
    
    private func check(data: Data, from response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorResponse: [deCONZErrorContext] = try decoder.decode([deCONZErrorContext].self, from: data)
            guard let errorContext = errorResponse.first else { throw deCONZError.unknownResponse(data: data, response: response) }
            throw deCONZError.apiError(context: errorContext)
        }
    }
    
    // MARK: - deCONZ Lights REST API Methods
    
    func getAllLights() async throws -> [Int: deCONZLight] {
        let path = "/api/\(self.keyAPI)/lights/"
        let request = request(forPath: path, using: .get)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let lightsResponse: [Int: deCONZLight] = try decoder.decode([Int : deCONZLight].self, from: data)
        return lightsResponse
    }
    
    // MARK: - deCONZ Groups REST API Methods
    
    func createGroup(name: String) async throws {
        let group = deCONZGroup(name: name)
        
        let path = "/api/\(self.keyAPI)/groups/"
        var request = request(forPath: path, using: .post)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(group)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
    func getAllGroups() async throws -> ([Int: deCONZGroup], [Int: [Int: deCONZScene]]) {
        struct SceneContainer: Decodable {
            var scenes: [deCONZScene]
        }
        
        let path = "/api/\(self.keyAPI)/groups/"
        let request = request(forPath: path, using: .get)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        // The response from the REST API bundles Scene information into the Group information. It avoids
        // the need to make two separate requests to obtain the information, but ever so slightly ruins
        // the consistency of the data structures used to hold the information, where Groups now hold
        // the names of their Scenes, but not the names of their Lights.
        // The code below separates Group and Scene information into their own containers, which are then
        // returned by the function as a tuple. The Group information retains only the IDs of its Scenes,
        // which is the same information it holds on its Lights. The Scene information is put in its own
        // object, index by the Group they belong to.
        
        let tempGroups: [Int: deCONZGroup] = try decoder.decode([Int: deCONZGroup].self, from: data)
        let tempScenes: [Int: SceneContainer] = try decoder.decode([Int: SceneContainer].self, from: data)
        var groupsResponse = [Int: deCONZGroup]()
        var scenesResponse = [Int: [Int: deCONZScene]]()
        
        for (key, group) in tempGroups {
            guard let scenes = tempScenes[key]?.scenes else { continue }
            
            // Copy an array of Light IDs from 'Scenes' into 'Groups'
            var groupCopy = group
            groupCopy.scenes = scenes.map { $0.id! }
            groupsResponse[key] = groupCopy
            
            // Copy an array of deCONZScene into the response
            scenesResponse[key] = [Int: deCONZScene]()
            for (scene) in scenes {
                if let stringSceneID = scene.id, let sceneID = Int(stringSceneID) {
                    scenesResponse[key]![sceneID] = scene
                }
            }
        }
        
        return (groupsResponse, scenesResponse)
    }
    
    func setGroupAttributes(groupID: Int, name: String? = nil, lights: [Int]? = nil) async throws {
        let group = deCONZGroup(name: name, lights: lights?.map({ String($0) }))
        
        let path = "/api/\(self.keyAPI)/groups/\(groupID)/"
        var request = request(forPath: path, using: .put)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(group)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
    func deleteGroup(groupID: Int) async throws {
        let path = "/api/\(self.keyAPI)/groups/\(groupID)/"
        let request = request(forPath: path, using: .delete)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
    // MARK: - deCONZ Scenes REST API Methods
    
    func createScene(groupID: Int, name: String) async throws {
        let scene = deCONZScene(name: name)
        
        let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes"
        var request = request(forPath: path, using: .post)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(scene)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
    func getSceneAttributes(groupID: Int, sceneID: Int) async throws -> [deCONZLightState] {
        struct LightStateContainer: Decodable {
            var lights: [deCONZLightState]
        }
        
        let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes/\(sceneID)/"
        let request = request(forPath: path, using: .get)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let tempLightStates: LightStateContainer = try decoder.decode(LightStateContainer.self, from: data)
        return tempLightStates.lights
    }
    
    func modifyScene(groupID: Int, sceneID: Int, lightIDs: [Int], state: String) async throws {
        // Build the request body by decoding and re-encoding 'state' to JSON (to 'validate' it).
        // Since 'state' is the same for all passed-in lights, this only needs to be done once.
        // Note that the deCONZ REST API is inconsistent in the way it handles xy Color Mode values.
        // When modifying a Scene that uses xy Color Mode, the values must be passed in as an array under
        // the "xy" JSON key. When getting the attributes of a Scene that uses xy Color Mode, the REST
        // API returns the values in separate "x" and "y" JSON keys.
        
        var lightState: deCONZLightState = try decoder.decode(deCONZLightState.self, from: state.data(using: .utf8)!)
        
        if lightState.colormode == "xy" {
            lightState.xy = [lightState.x!, lightState.y!]
            lightState.x = nil
            lightState.y = nil
        }
        
        for (lightID) in lightIDs {
            let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes/\(sceneID)/lights/\(lightID)/state/"
            var request = request(forPath: path, using: .put)
            encoder.outputFormatting = []
            request.httpBody = try encoder.encode(lightState)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(data: data, from: response)
            
            // TODO: Pace consecutive requests
            //       deCONZ won't be able to handle a string of requests one after the other. Even though
            //       it will happily accept them, the Zigbee network takes some time to propagate all the
            //       messages that result from each HTTP request. The messages pile up in the outgoing
            //       Zigbee queue until the queue gets full and deCONZ starts to drop messages.
            //
            //       try await Task.sleep(nanoseconds: 300_000_000) ???
        }
    }
    
    func deleteScene(groupID: Int, sceneID: Int) async throws {
        let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes/\(sceneID)/"
        let request = request(forPath: path, using: .delete)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
}
