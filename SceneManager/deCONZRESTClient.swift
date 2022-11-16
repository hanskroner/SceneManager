//
//  deCONZClient.swift
//  SceneManager
//
//  Created by Hans Kröner on 05/11/2022.
//

import Foundation

// MARK: - REST API Models

private extension deCONZRESTClient {
    struct deCONZLightStateRESTParameter: Codable, Hashable {
        var id: String?
        var on: Bool?
        var bri: Int?
        var transitiontime: Int?
        var colormode: String?
        var ct: Int?
        var x: Double?
        var y: Double?
        var xy: [Double]?
    }
    
    struct deCONZLightRESTParameter: Codable, Hashable {
        var id: String?
        var name: String?
        var manufacturer: String?
        var modelid: String?
        var type: String?
        var state: deCONZLightStateRESTParameter?
    }
    
    struct deCONZSceneRESTParameter: Codable, Hashable {
        var id: String?
        var name: String?
        var transitiontime: Int?
        var lightcount: Int?
    }
    
    struct deCONZGroupRESTParameter: Codable, Hashable {
        var id: String?
        var name: String?
        var lights: [String]?
        var scenes: [deCONZSceneRESTParameter]?
        var devicemembership: [String]?
    }
    
    func deconzLightState(from restLightState: deCONZLightStateRESTParameter) -> deCONZLightState {
        var colorMode: deCONZLightColorMode
        if (restLightState.colormode == "ct") {
            colorMode = .ct(restLightState.ct!)
        } else if (restLightState.colormode == "xy") {
            if (restLightState.xy != nil) {
                colorMode = .xy(restLightState.xy![0], restLightState.xy![1])
            } else if ((restLightState.x != nil) && (restLightState.y != nil)) {
                colorMode = .xy(restLightState.x!, restLightState.y!)
            } else {
                // FIXME: Handle errors
                fatalError("'colormode' is incorrect")
            }
        } else {
            // !!!: 'hs' mode (Hue/Saturation) is not supported
            colorMode = .ct(150)
        }
        
        return deCONZLightState(on: restLightState.on!,
                                      bri: restLightState.bri!,
                                      transitiontime: restLightState.transitiontime,
                                      colormode: colorMode)
    }
    
    func deconzLightStateRESTParameter(from lightState: deCONZLightState?) -> deCONZLightStateRESTParameter {
        guard let lightState = lightState else { return deCONZLightStateRESTParameter() }
        
        var colormode: String? = nil
        var ct: Int? = nil
        var xy: [Double]? = nil
        
        // !!!: 'hs' mode (Hue/Saturation) is not supported
        switch (lightState.colormode) {
        case .ct(let ct_val):
            colormode = "ct"
            ct = ct_val
            
        case .xy(let x_val, let y_val):
            colormode = "xy"
            xy = [x_val, y_val]
        }
        
        return deCONZLightStateRESTParameter(id: nil,
                                             on: lightState.on,
                                             bri: lightState.bri,
                                             transitiontime: lightState.transitiontime,
                                             colormode: colormode,
                                             ct: ct,
                                             xy: xy)
    }
    
    func deconzLight(from restLight: deCONZLightRESTParameter, lightID: Int) -> deCONZLight? {
        return deCONZLight(id: lightID,
                           name: restLight.name ?? "",
                           manufacturer: restLight.manufacturer ?? "",
                           modelid: restLight.modelid ?? "",
                           type: restLight.type ?? "")
    }
    
    func deconzGroup(from restGroup: deCONZGroupRESTParameter) -> deCONZGroup? {
        // Ignore Groups where 'devicemembership' is not empty
        // These groups are created by switches or sensors and are not the kind we're looking for.
        guard (restGroup.devicemembership?.isEmpty ?? false) else { return nil }
        
        return deCONZGroup(id: Int(restGroup.id!)!,
                           name: restGroup.name ?? "",
                           lights: (restGroup.lights ?? []).map { Int($0)! },
                           scenes: (restGroup.scenes ?? []).map { Int($0.id!)! })
    }
    
    func deconzScene(from restScene: deCONZSceneRESTParameter, groupID: Int) -> deCONZScene {
        return deCONZScene(id: Int(restScene.id!)!,
                           gid: groupID,
                           name: restScene.name ?? "")
    }
}

actor deCONZRESTClient: ObservableObject {
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
        
        let lightsResponse: [Int: deCONZLightRESTParameter] = try decoder.decode([Int : deCONZLightRESTParameter].self, from: data)
        
        var lights = [Int: deCONZLight]()
        for (key, value) in lightsResponse {
            lights[key] = deconzLight(from: value, lightID: key)
        }
        
        return lights
    }
    
    func getLightState(lightID: Int) async throws -> deCONZLightState {
        struct LightStateContainer: Decodable {
            var state: deCONZLightStateRESTParameter
        }
        
        let path = "/api/\(self.keyAPI)/lights/\(lightID)"
        let request = request(forPath: path, using: .get)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let stateResponse: LightStateContainer = try decoder.decode(LightStateContainer.self, from: data)
        let state = deconzLightState(from: stateResponse.state)
        
        return state
    }
    
    // MARK: - deCONZ Groups REST API Methods
    
    func createGroup(name: String) async throws -> Int {
        let group = deCONZGroupRESTParameter(name: name)
        
        let path = "/api/\(self.keyAPI)/groups/"
        var request = request(forPath: path, using: .post)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(group)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let successResponse: [deCONZSuccessContext] = try decoder.decode([deCONZSuccessContext].self, from: data)
        guard let successContext = successResponse.first,
              let responseID = Int(successContext.id)
        else { throw deCONZError.unknownResponse(data: data, response: response) }
        
        return responseID
    }
    
    func getAllGroups() async throws -> ([Int: deCONZGroup], [Int: [Int: deCONZScene]]) {
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
        
        let groupsResponse: [Int: deCONZGroupRESTParameter] = try decoder.decode([Int: deCONZGroupRESTParameter].self, from: data)
        
        let groups = groupsResponse.compactMapValues { deconzGroup(from: $0) }
        let scenes = groupsResponse.compactMapValues { restGroup in
            restGroup.scenes?.reduce(into: [Int: deCONZScene]()) {
                let scene = deconzScene(from: $1, groupID: Int(restGroup.id!)!)
                $0[scene.id] = scene
            }
        }
        
        return (groups, scenes)
    }
    
    func setGroupAttributes(groupID: Int, name: String? = nil, lights: [Int]? = nil) async throws {
        let group = deCONZGroupRESTParameter(name: name, lights: lights?.map({ String($0) }))
        
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
    
    func createScene(groupID: Int, name: String) async throws -> Int {
        let scene = deCONZSceneRESTParameter(name: name)
        
        let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes"
        var request = request(forPath: path, using: .post)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(scene)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let successResponse: [deCONZSuccessContext] = try decoder.decode([deCONZSuccessContext].self, from: data)
        guard let successContext = successResponse.first,
              let responseID = Int(successContext.id)
        else { throw deCONZError.unknownResponse(data: data, response: response) }
        
        return responseID
    }
    
    func getSceneAttributes(groupID: Int, sceneID: Int) async throws -> [Int: deCONZLightState] {
        struct LightStateContainer: Decodable {
            var lights: [deCONZLightStateRESTParameter]
        }
        
        let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes/\(sceneID)/"
        let request = request(forPath: path, using: .get)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
        
        let tempLightStates: LightStateContainer = try decoder.decode(LightStateContainer.self, from: data)
        
        var lightStates = [Int: deCONZLightState]()
        
        for (restLightState) in tempLightStates.lights {
            if let stringLightID = restLightState.id,
               let lightID = Int(stringLightID) {
                lightStates[lightID] = deconzLightState(from: restLightState)
            }
        }
        
        return lightStates
    }
    
    func setSceneAttributes(groupID: Int, sceneID: Int, name: String) async throws {
        let scene = deCONZSceneRESTParameter(name: name)
        
        let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes/\(sceneID)/"
        var request = request(forPath: path, using: .put)
        encoder.outputFormatting = []
        request.httpBody = try encoder.encode(scene)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
    func modifyScene(groupID: Int, sceneID: Int, lightIDs: [Int], state: deCONZLightState?) async throws {
        // Build the request body by decoding and re-encoding 'state' to JSON (to 'validate' it).
        // Since 'state' is the same for all passed-in lights, this only needs to be done once.
        // Note that the deCONZ REST API is inconsistent in the way it handles xy Color Mode values.
        // When modifying a Scene that uses xy Color Mode, the values must be passed in as an array under
        // the "xy" JSON key. When getting the attributes of a Scene that uses xy Color Mode, the REST
        // API returns the values in separate "x" and "y" JSON keys.
        
        // Note that 'deconzLightStateRESTParameter' sets 'id' to nil and only returns 'xy'
        // colormode as an Array of Doubles.
        let restLightState = deconzLightStateRESTParameter(from: state)
        
        for (lightID) in lightIDs {
            let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes/\(sceneID)/lights/\(lightID)/state/"
            var request = request(forPath: path, using: .put)
            encoder.outputFormatting = []
            request.httpBody = try encoder.encode(restLightState)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(data: data, from: response)
        }
    }
    
    func storeScene(groupID: Int, sceneID: Int) async throws {
        let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes/\(sceneID)/store"
        let request = request(forPath: path, using: .put)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
    
    func deleteScene(groupID: Int, sceneID: Int) async throws {
        let path = "/api/\(self.keyAPI)/groups/\(groupID)/scenes/\(sceneID)/"
        let request = request(forPath: path, using: .delete)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data: data, from: response)
    }
}
