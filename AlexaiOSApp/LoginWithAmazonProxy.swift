//
//  LoginWithAmazon.swift
//  Alexa iOS App
//
//

import Foundation
import LoginWithAmazon

class LoginWithAmazonProxy {

    static let sharedInstance = LoginWithAmazonProxy()

    func login(delegate: AIAuthenticationDelegate) {
        AIMobileLib.authorizeUser(forScopes: Settings.Credentials.SCOPES, delegate: delegate, options: [kAIOptionScopeData: Settings.Credentials.SCOPE_DATA])
    }
    
    func logout(delegate: AIAuthenticationDelegate) {
        AIMobileLib.clearAuthorizationState(delegate)
    }
    
    func getAccessToken(delegate: AIAuthenticationDelegate) {
        AIMobileLib.getAccessToken(forScopes: Settings.Credentials.SCOPES, withOverrideParams: nil, delegate: delegate)
    }
}
