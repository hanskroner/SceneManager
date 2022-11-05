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
}
