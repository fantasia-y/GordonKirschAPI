//
//  KeychainStorage.swift
//
//
//  Created by Gordon on 12.12.23.
//

import Foundation
import KeychainSwift

public class KeychainStorage {
    public static let shared = KeychainStorage()
    private let keychain = KeychainSwift()
    
    public func saveToken(response: LoginResponse) {
        keychain.set(response.accessToken, forKey: "accessToken")
        keychain.set(response.refreshToken, forKey: "refreshToken")
    }
    
    public func clearTokens() {
        keychain.delete("accessToken")
        keychain.delete("refreshToken")
    }
    
    public func getAccessToken() -> Token {
        return Token(token: keychain.get("accessToken") ?? "")
    }
    
    public func getRefreshToken() -> Token {
        return Token(token: keychain.get("refreshToken") ?? "", expiresAt: 0)
    }
}
