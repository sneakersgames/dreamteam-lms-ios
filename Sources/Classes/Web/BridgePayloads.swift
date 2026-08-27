import ConsentViewController
import Foundation
import GamesLib

/// Builds the JSON payloads the web side expects, from ghcore's Swift types.
enum BridgePayloads {

    // MARK: env.get

    /// `GamingHubCardsEnvironment` is not `Codable`, so the dictionary is built
    /// field by field. `sessionKey` and `launchUrl` are additions the web side
    /// needs that ghcore does not provide.
    static func environment(launchUrl: String?) -> [String: Any] {
        let env = GamingHubCards.environment
        return [
            "environment": env.environment.rawValue,
            "language": env.language,
            "competition": env.competition,
            "season": env.season,
            "timezone": env.timezone,
            "appId": env.appId,
            "clientId": env.clientId,
            "appVersion": env.appVersion,
            "gameId": GameConfig.gameId,
            "sessionKey": GameConfig.sessionKey ?? NSNull(),
            "launchUrl": launchUrl ?? NSNull(),
        ]
    }

    // MARK: user.get / user.changed

    /// Built field-by-field. `GHUser.encode(to:)` is custom and has dropped or
    /// renamed fields in ways that make the web adapter treat a signed-in hub
    /// user as anonymous (it requires `userId` + `token.token`).
    static func user() -> [String: Any] {
        let isLoggedIn = GamingHubCards.isLoggedIn
        let user = GamingHubCards.user
        let accessToken = user.token?.token
        let hasToken = accessToken?.isEmpty == false

        var userId: Any = user.userId ?? NSNull()
        if user.userId == nil, let sub = jwtSubject(from: accessToken) {
            if let numeric = Int(sub) {
                userId = numeric
            } else {
                userId = sub
            }
        }

        if isLoggedIn, !hasToken {
            print("[ghbridge] user.get: logged in but no access token; web will stay anonymous")
        }
        if isLoggedIn, user.userId == nil {
            print("[ghbridge] user.get: GHUser.userId is nil; using JWT sub if present")
        }

        print("[ghbridge] user.get isLoggedIn=\(isLoggedIn) anonymous=\(user.anonymous) userId=\(String(describing: user.userId)) hasToken=\(hasToken) sessionKeyLen=\(GameConfig.sessionKey?.count ?? 0)")

        let encoded: [String: Any] = [
            "userId": userId,
            "uefaId": user.uefaId ?? NSNull(),
            "username": user.username,
            // The web adapter refuses `anonymous: true` even when isLoggedIn.
            "anonymous": !(isLoggedIn && hasToken),
            "nextLevelXP": user.nextLevelXP,
            "nextLevel": user.nextLevel,
            "levelName": user.levelName,
            "level": user.level,
            "levelColor": user.levelColor,
            "xp": user.xp,
            "startingXP": user.startingXP,
            "avatar": [
                "id": user.avatar.id,
                "url": user.avatar.url,
            ],
            "countryCode": user.countryCode ?? NSNull(),
            "favouriteClub": user.favouriteClub ?? NSNull(),
            "isFirstSeason": user.isFirstSeason,
            "isMiniRegistartionCompleted": user.isMiniRegistartionCompleted,
            "token": tokenPayload(user.token),
        ]

        return [
            "isLoggedIn": isLoggedIn,
            "user": encoded,
        ]
    }

    private static func tokenPayload(_ token: GHUserToken?) -> Any {
        guard let token else { return NSNull() }
        let payload: [String: Any] = [
            "token": token.token ?? NSNull(),
            "expirationDate": token.expirationDate.map { iso8601.string(from: $0) } ?? NSNull(),
        ]
        return payload
    }

    /// Unverified read of `sub` from a JWT payload. Used only when ghcore
    /// omitted `userId`; the server still verifies the token later.
    private static func jwtSubject(from token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let sub = json["sub"] as? String, sub.isEmpty == false { return sub }
        if let sub = json["sub"] as? Int { return String(sub) }
        return nil
    }

    private static let iso8601 = ISO8601DateFormatter()

    // MARK: consent.get / consent.changed

    /// Consent is only ever reported as held when SourcePoint actually has it,
    /// since claiming otherwise makes the web CMP wait for data that never arrives.
    static func consent() -> [String: Any] {
        guard let consent: SPUserData = AdsConsentManager.consent else {
            return ["hasConsent": false]
        }

        var payload: [String: Any] = ["hasConsent": true]
        if let gdpr = consent.gdpr {
            payload["gdprApplies"] = gdpr.applies
            if let tcString = gdpr.consents?.euconsent, tcString.isEmpty == false {
                payload["tcString"] = tcString
            }
        }
        return payload
    }

}
