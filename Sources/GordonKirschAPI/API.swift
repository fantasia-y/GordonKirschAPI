//
//  API.swift
//
//  Created by Gordon on 30.03.23.
//

import Foundation
import Network

public class Errors {
    //internal
    public static let ERR_SERIALIZING_REQUEST = "error_serializing_request"
    public static let ERR_CONVERTING_TO_HTTP_RESPONSE = "error_converting_response_to_http_response"
    public static let ERR_PARSE_RESPONSE = "error_parsing_response"
    public static let ERR_NIL_BODY = "error_nil_body"
    public static let ERR_PARSE_ERROR_RESPONSE = "error_parsing_error_response"
    
    //server
    public static let ERR_WRONG_CREDENTIALS = "Invalid credentials."
    public static let ERR_MISSING_AUTH_HEADER = "JWT Token not found"
    public static let ERR_INVALID_ACCESS_TOKEN = "Invalid JWT Token"
    public static let ERR_ACCESS_TOKEN_EXPIRED = "Expired JWT Token"
    public static let ERR_INVALID_REFRESH_TOKEN = "JWT Refresh Token Not Found"
    public static let ERR_REFRESH_TOKEN_EXPIRED = "Invalid JWT Refresh Token"
    
    public static func messageFor(err: String) -> String {
        switch err {
        case ERR_WRONG_CREDENTIALS:
            return "Entered wrong login or password"
        default:
            return "An error has occured. Please check your internet connection and try again."
        }
    }
    
    public static func isAuthError(err: String) -> Bool {
        return [ERR_MISSING_AUTH_HEADER, ERR_INVALID_ACCESS_TOKEN, ERR_INVALID_REFRESH_TOKEN, ERR_ACCESS_TOKEN_EXPIRED, ERR_REFRESH_TOKEN_EXPIRED].contains(where: { $0 == err })
    }
}

public struct LoginResponse: Decodable {
    var accessToken: String
    var refreshToken: String
    var refreshTokenExpiration: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "token"
        case refreshToken = "refresh_token"
        case refreshTokenExpiration = "refresh_token_expiration"
    }
}

public struct ErrorResponse: Codable {
    public let code: Int
    public let message: String
    
    public func isAuth() -> Bool {
        return Errors.isAuthError(err: message) || code == 403
    }
}

public struct EmptyResponse: Codable {}

public enum ApiResult<T> {
    case success(_ response: T)
    case serverError(_ err: ErrorResponse)
    case authError(_ err: ErrorResponse)
    case networkError(_ err: String)
}

public enum RequestMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
    case put = "PUT"
}

public enum NetworkStatus {
    case online
    case offline
}

public class API {
    private static var url: String {
        return Bundle.main.infoDictionary?["API_URL"] as! String
    }
    
    public static let shared = API(url)
    public var networkStatus: NetworkStatus = .online
    
    private let monitor = NWPathMonitor()
    private let baseUrl: String
    private let ACCESS_TOKEN_THRESHOLD_SECONDS = 10
    private var accessToken = KeychainStorage.shared.getAccessToken()
    private var refreshToken = KeychainStorage.shared.getRefreshToken()
    
    init(_ baseUrl: String) {
        self.baseUrl = baseUrl
        
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            
            if path.status == .satisfied {
                networkStatus = .online
                print("Network is online")
            } else {
                networkStatus = .offline
                print("Network is offline")
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }
    
    public func getBaseUrl() -> String {
        return baseUrl
    }
    
    public func hasAccessToken() -> Bool {
        return !accessToken.token.isEmpty
    }
    
    private func getFullUrl(forPath path: String) -> URL {
        return URL(string: self.baseUrl + path)!
    }
    
    private func append(parameters: [String: String], toUrl url: URL) -> URL {
        var urlComponents = URLComponents(string: url.absoluteString)!
        urlComponents.queryItems = parameters.map({ key, value in URLQueryItem(name: key, value: value) })
        return urlComponents.url!
    }
    
    private func onTokensRefreshed(response: LoginResponse) {
        KeychainStorage.shared.saveToken(response: response)
        accessToken = Token(token: response.accessToken)
        refreshToken = Token(token: response.refreshToken, expiresAt: response.refreshTokenExpiration)
    }
    
    private func formRequest(
        path: String,
        data: Encodable? = nil,
        query: [String: String]? = nil,
        method: RequestMethod = .post,
        contentType: String = "application/json",
        refreshToken: Bool = false,
        ignoreJwtAuth: Bool = false
    ) -> URLRequest {
        // set url
        var url = getFullUrl(forPath: path)
        
        if let query, !query.isEmpty {
            url = append(parameters: query, toUrl: url)
        }
        
        // create request
        var request = URLRequest(
            url: url,
            cachePolicy: networkStatus == .online ? .reloadIgnoringLocalCacheData : .returnCacheDataDontLoad
        )
        
        // simulator add xdebug cookie
        #if targetEnvironment(simulator)
        if let cookie = HTTPCookie(properties: [
            .domain: baseUrl,
            .path: "/",
            .name: "XDEBUG_SESSION",
            .value: "PHPSTORM"
        ]) {
            request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: [cookie])
        }
        #endif
        
        request.httpMethod = method.rawValue
        request.addValue(contentType, forHTTPHeaderField: "Content-Type")
        
        // add auth headers
        if refreshToken {
            request.addValue(self.refreshToken.token, forHTTPHeaderField: "X-Refresh-Token")
        }
        if !accessToken.token.isEmpty && !ignoreJwtAuth {
            request.addValue("Bearer \(accessToken.token)", forHTTPHeaderField: "Authorization")
        }
        
        // add post data
        if let data {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            
            request.httpBody = try! encoder.encode(data)
        }
        
        return request
    }
    
    private func formRefreshTokensRequest() -> URLRequest {
        return formRequest(path: "/token/refresh", refreshToken: true, ignoreJwtAuth: true)
    }
    
    private func renewAuthHeader(request: URLRequest) -> URLRequest {
        var newRequest = request
        newRequest.setValue("Bearer \(accessToken.token)", forHTTPHeaderField: "Authorization")
        return newRequest
    }
    
    private func handleAuthResponse(response: ApiResult<LoginResponse>) {
        if case .success(let res) = response {
            self.onTokensRefreshed(response: res)
        }
    }
    
    public func login(email: String, password: String) async -> ApiResult<LoginResponse> {
        let request = formRequest(path: "/login", data: ["email": email, "password": password], ignoreJwtAuth: true)
        let response = await doRequest(request: request, decode: LoginResponse.self)
        handleAuthResponse(response: response)
        return response
    }
    
    public func login(fromURL url: URL) -> ApiResult<LoginResponse> {
        do {
            let params = url.extractParams()
            
            guard
                let accessToken = params.first(where: { $0.name == "token" })?.value,
                let refreshToken = params.first(where: { $0.name == "refresh_token" })?.value,
                let refreshTokenExpiration = params.first(where: { $0.name == "refresh_token_expiration" })?.value
            else {
                throw URLError(.badURL)
            }
            
            let response = ApiResult.success(LoginResponse(accessToken: accessToken, refreshToken: refreshToken, refreshTokenExpiration: Int(refreshTokenExpiration)!))
            handleAuthResponse(response: response)
            return response
        } catch {
            print(error)
            return ApiResult.serverError(ErrorResponse(code: 0, message: "Temp"))
        }
    }
    
    public func login(withIDToken token: String, fromProvider provider: String) async -> ApiResult<LoginResponse> {
        let request = formRequest(path: "/connect/token", data: ["provider": provider, "token": token], ignoreJwtAuth: true)
        let response = await doRequest(request: request, decode: LoginResponse.self)
        handleAuthResponse(response: response)
        return response
    }
    
    public func register(email: String, password: String) async -> ApiResult<LoginResponse> {
        let request = formRequest(path: "/register", data: ["email": email, "password": password], ignoreJwtAuth: true)
        let response = await doRequest(request: request, decode: LoginResponse.self)
        handleAuthResponse(response: response)
        return response
    }
    
    public func logout() async {
        // TODO invalidate refresh token on server
        
        accessToken = Token(token: "", expiresAt: 0)
        refreshToken = Token(token: "", expiresAt: 0)
        KeychainStorage.shared.clearTokens()
    }
    
    public func generateConnectUrl(forProvider provider: String, redirectTo: String) -> URL {
        return append(parameters: ["provider": provider, "redirect_to": redirectTo], toUrl: getFullUrl(forPath: "/connect"))
    }
    
    private var needReAuth: Bool {
        let current = Date().timestamp()
        let expires = accessToken.expiresAt
        return current + ACCESS_TOKEN_THRESHOLD_SECONDS > expires
    }
    
    public func post<T: Decodable>(path: String, decode: T.Type, parameters: Encodable? = nil) async -> ApiResult<T> {
        let request = formRequest(path: path, data: parameters, method: .post)
        return await self.request(request: request, decode: decode)
    }
    
    public func post(path: String, parameters: Encodable? = nil) async -> ApiResult<EmptyResponse> {
        let request = formRequest(path: path, data: parameters, method: .post)
        return await self.request(request: request, decode: EmptyResponse.self)
    }
    
    public func put<T: Decodable>(path: String, decode: T.Type, parameters: Encodable? = nil) async -> ApiResult<T> {
        let request = formRequest(path: path, data: parameters, method: .put)
        return await self.request(request: request, decode: decode)
    }
    
    public func put(path: String, parameters: Encodable? = nil) async -> ApiResult<EmptyResponse> {
        let request = formRequest(path: path, data: parameters, method: .put)
        return await self.request(request: request, decode: EmptyResponse.self)
    }
    
    public func get<T: Decodable>(path: String, decode: T.Type, parameters: [String: String]? = nil) async -> ApiResult<T> {
        let request = formRequest(path: path, query: parameters, method: .get)
        return await self.request(request: request, decode: decode)
    }
    
    public func get(path: String, parameters: [String: String]? = nil) async -> ApiResult<EmptyResponse> {
        let request = formRequest(path: path, query: parameters, method: .get)
        return await self.request(request: request, decode: EmptyResponse.self)
    }
    
    public func delete<T: Decodable>(path: String, decode: T.Type, parameters: Encodable? = nil) async -> ApiResult<T> {
        let request = formRequest(path: path, data: parameters, method: .delete)
        return await self.request(request: request, decode: decode)
    }
    
    public func delete(path: String, parameters: Encodable? = nil) async -> ApiResult<EmptyResponse> {
        let request = formRequest(path: path, data: parameters, method: .delete)
        return await self.request(request: request, decode: EmptyResponse.self)
    }
    
    private func request<T: Decodable>(request: URLRequest, decode: T.Type) async -> ApiResult<T> {
        if (needReAuth && !refreshToken.token.isEmpty) {
            print("[REQUEST] re-auth required")
            return await authAndDoRequest(request: request, decode: decode)
        } else {
            return await doRequest(request: request, decode: decode)
        }
    }
    
    private func authAndDoRequest<T: Decodable>(request: URLRequest, decode: T.Type) async -> ApiResult<T> {
        let refreshRequest = formRefreshTokensRequest()
        
        do {
            let (data, response) = try await URLSession.shared.data(for: refreshRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .authError(ErrorResponse(code: 0, message: Errors.ERR_CONVERTING_TO_HTTP_RESPONSE))
            }
            
            if httpResponse.isSuccessful() {
                do {
                    let response = try JSONDecoder().decode(LoginResponse.self, from: data)
                    print("[REQUEST] refresh token response: \(response)")
                    onTokensRefreshed(response: response)

                    let newRequest = renewAuthHeader(request: request)
                    return await doRequest(request: newRequest, decode: decode)
                } catch {
                    return .authError(ErrorResponse(code: 0, message: Errors.ERR_PARSE_RESPONSE))
                }
            } else {
                do {
                    let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
                    return .authError(errorResponse)
                } catch {
                    return .authError(ErrorResponse(code: 0, message: error.localizedDescription))
                }
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
    
    private func doRequest<T: Decodable>(request: URLRequest, decode: T.Type) async -> ApiResult<T> {
        print("[REQUEST] \(request.httpMethod!) \(request.url?.absoluteString ?? "")")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .networkError(Errors.ERR_CONVERTING_TO_HTTP_RESPONSE)
            }

            print("[REQUEST] respone code: \(httpResponse.statusCode)")
            if httpResponse.isSuccessful() {
                return self.parseResponse(data: data)
            } else {
                return self.parseError(data: data)
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
    
    private func parseResponse<T: Decodable>(data: Data) -> ApiResult<T> {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            return .success(try decoder.decode(T.self, from: data))
        } catch {
            print("failed parsing successful response, parsing err: \(error)")
            return parseError(data: data)
        }
    }
    
    private func parseError<T>(data: Data) -> ApiResult<T> {
        print("parsing error")
        do {
            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
            if (errorResponse.isAuth()) {
                return .authError(errorResponse)
            } else {
                return .serverError(errorResponse)
            }
        } catch {
            return .serverError(ErrorResponse(code: 0, message: Errors.ERR_PARSE_ERROR_RESPONSE))
        }
    }
}
