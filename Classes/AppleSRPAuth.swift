import Foundation
import CryptoKit
import SRP
import CommonCrypto

@objc(AppleSRPAuth)
public final class AppleSRPAuth: NSObject {
    private static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"

    private enum ProofEncoding: String {
        case base64
    }

    @objc(signInWithAccountName:password:widgetKey:baseURLString:)
    public class func signIn(accountName: String, password: String, widgetKey: String, baseURLString: String) -> NSDictionary? {
        signInOnce(accountName: accountName, password: password, widgetKey: widgetKey, baseURLString: baseURLString, proofEncoding: .base64)
    }

    @objc(resolveAuthConfigurationWithDefaultWidgetKey:defaultBaseURLString:)
    public class func resolveAuthConfiguration(defaultWidgetKey: String, defaultBaseURLString: String) -> NSDictionary {
        var widgetKey = defaultWidgetKey
        var baseURLString = defaultBaseURLString

        if let config = fetchAuthConfiguration() {
            let authServiceKey = config["authServiceKey"] as? String
                ?? config["authServiceWidgetKey"] as? String
                ?? config["widgetKey"] as? String
            let authServiceURL = config["authServiceUrl"] as? String
                ?? config["authServiceURL"] as? String
                ?? config["authBaseUrl"] as? String

            if let authServiceKey, !authServiceKey.isEmpty {
                widgetKey = authServiceKey
            }
            if let authServiceURL, !authServiceURL.isEmpty {
                baseURLString = authServiceURL
            }
        }

        return [
            "widgetKey": widgetKey,
            "baseURLString": baseURLString
        ]
    }

    private class func signInOnce(accountName: String, password: String, widgetKey: String, baseURLString: String, proofEncoding: ProofEncoding) -> NSDictionary? {
        guard let baseURL = URL(string: baseURLString) else { return nil }
        guard !accountName.isEmpty, !password.isEmpty else { return nil }

        let configuration = SRPConfiguration<SHA256>(.N2048)
        let client = SRPClient(configuration: configuration)
        let clientKeys = client.generateKeys()
        let clientPublicKey = clientKeys.public
        let aBodyValue = Data(clientPublicKey.bytes).base64EncodedString()

        guard let hashcashHeader = fetchHashcash(baseURL: baseURL, widgetKey: widgetKey), !hashcashHeader.isEmpty else {
            return [
                "stage": "hashcash",
                "error": "missing-hashcash",
                "proofEncoding": proofEncoding.rawValue
            ]
        }

        let initBody: [String: Any] = [
            "a": aBodyValue,
            "accountName": accountName,
            "protocols": ["s2k", "s2k_fo"]
        ]
        guard let initData = try? JSONSerialization.data(withJSONObject: initBody) else { return nil }

        guard let initURL = authEndpointURL(baseURL: baseURL, pathSuffix: "signin/init") else { return nil }
        var initRequest = URLRequest(url: initURL)
        initRequest.httpMethod = "POST"
        initRequest.httpBody = initData
        applyFastlaneSharedHeaders(request: &initRequest, widgetKey: widgetKey)
        if let modifiedCookie = modifiedCookieHeader(for: initURL) {
            initRequest.setValue(modifiedCookie, forHTTPHeaderField: "Cookie")
        }

        let maxInitAttempts = 3
        var initAttempt = 0
        var initResponse: HTTPURLResponse?
        var initPayload: [String: Any] = [:]

        while initAttempt < maxInitAttempts {
            initAttempt += 1
            let initResult = sendSynchronous(request: initRequest)
            initResponse = initResult.response
            initPayload = parseJSONDict(data: initResult.data) ?? [:]

            if initResponse?.statusCode == 503 && initAttempt < maxInitAttempts {
                let delay = Double(initAttempt) * 1.5
                Thread.sleep(forTimeInterval: delay)
                continue
            }
            break
        }

        guard let initResponse else { return nil }
        if initResponse.statusCode >= 400 {
            return [
                "statusCode": initResponse.statusCode,
                "stage": "signin/init",
                "errorPayload": initPayload,
                "attempts": initAttempt,
                "proofEncoding": proofEncoding.rawValue
            ]
        }

        guard
            let saltValue = initPayload["salt"] as? String,
            let bValue = initPayload["b"] as? String,
            let challengeValue = initPayload["c"] as? String
        else {
            return nil
        }

        guard let saltData = decodeSRPData(saltValue) else {
            return [
                "statusCode": initResponse.statusCode,
                "stage": "signin/init",
                "error": "invalid-salt-format",
                "errorPayload": initPayload
            ]
        }

        guard let bData = decodeSRPData(bValue) else {
            return [
                "statusCode": initResponse.statusCode,
                "stage": "signin/init",
                "error": "invalid-b-format",
                "errorPayload": initPayload
            ]
        }
        guard let iteration = initPayload["iteration"] as? Int else {
            return [
                "statusCode": initResponse.statusCode,
                "stage": "signin/init",
                "error": "missing-iteration",
                "errorPayload": initPayload
            ]
        }
        let serverPublicKey = SRPKey([UInt8](bData))
        var sessionId = initResponse.value(forHTTPHeaderField: "X-Apple-ID-Session-Id") ?? ""
        var scnt = initResponse.value(forHTTPHeaderField: "scnt") ?? ""

        let saltBytes = [UInt8](saltData)
        guard let encryptedPassword = pbkdf2(password: password, saltData: saltData, rounds: iteration) else {
            return [
                "statusCode": initResponse.statusCode,
                "stage": "signin/pbkdf2",
                "error": "pbkdf2-failed",
                "proofEncoding": proofEncoding.rawValue,
                "passwordMode": "sha256_pbkdf2"
            ]
        }

        let sharedSecret: SRPKey
        do {
            sharedSecret = try client.calculateSharedSecret(
                password: encryptedPassword,
                salt: saltBytes,
                clientKeys: clientKeys,
                serverPublicKey: serverPublicKey
            )
        } catch {
            return [
                "statusCode": initResponse.statusCode,
                "stage": "signin/shared-secret",
                "error": String(describing: error),
                "proofEncoding": proofEncoding.rawValue,
                "passwordMode": "sha256_pbkdf2"
            ]
        }

        let m1Bytes = client.calculateClientProof(
            username: accountName,
            salt: saltBytes,
            clientPublicKey: clientPublicKey,
            serverPublicKey: serverPublicKey,
            sharedSecret: sharedSecret
        )
        let m2Bytes = client.calculateServerProof(
            clientPublicKey: clientPublicKey,
            clientProof: m1Bytes,
            sharedSecret: sharedSecret
        )

        let completeBody: [String: Any] = [
            "accountName": accountName,
            "rememberMe": false,
            "m1": Data(m1Bytes).base64EncodedString(),
            "m2": Data(m2Bytes).base64EncodedString(),
            "c": challengeValue
        ]
        guard let completeData = try? JSONSerialization.data(withJSONObject: completeBody) else { return nil }

        guard let completeBaseURL = authEndpointURL(baseURL: baseURL, pathSuffix: "signin/complete") else { return nil }
        guard var completeComponents = URLComponents(url: completeBaseURL, resolvingAgainstBaseURL: false) else { return nil }
        completeComponents.queryItems = [URLQueryItem(name: "isRememberMeEnabled", value: "false")]
        guard let completeURL = completeComponents.url else { return nil }

        var completeRequest = URLRequest(url: completeURL)
        completeRequest.httpMethod = "POST"
        completeRequest.httpBody = completeData
        applyFastlaneSharedHeaders(request: &completeRequest, widgetKey: widgetKey)
        if let modifiedCookie = modifiedCookieHeader(for: completeURL) {
            completeRequest.setValue(modifiedCookie, forHTTPHeaderField: "Cookie")
        }
        if !sessionId.isEmpty {
            completeRequest.setValue(sessionId, forHTTPHeaderField: "X-Apple-ID-Session-Id")
        }
        if !scnt.isEmpty {
            completeRequest.setValue(scnt, forHTTPHeaderField: "scnt")
        }
        completeRequest.setValue(hashcashHeader, forHTTPHeaderField: "X-Apple-HC")

        let completeResult = sendSynchronous(request: completeRequest)
        guard let completeResponse = completeResult.response else { return nil }

        let completeSession = completeResponse.value(forHTTPHeaderField: "X-Apple-ID-Session-Id") ?? ""
        let completeScnt = completeResponse.value(forHTTPHeaderField: "scnt") ?? ""
        var completeLocation = completeResponse.value(forHTTPHeaderField: "Location") ?? ""
        if sessionId.isEmpty { sessionId = completeSession }
        if scnt.isEmpty { scnt = completeScnt }

        if completeResponse.statusCode >= 400 {
            let completePayload = parseJSONDict(data: completeResult.data) ?? [:]
            if completeLocation.isEmpty, completePayload["authType"] != nil {
                completeLocation = "/auth"
            }

            return [
                "sessionId": sessionId,
                "scnt": scnt,
                "location": completeLocation,
                "statusCode": completeResponse.statusCode,
                "stage": "signin/complete",
                "errorPayload": completePayload,
                "proofEncoding": proofEncoding.rawValue,
                "passwordMode": "sha256_pbkdf2"
            ]
        }

        return [
            "sessionId": sessionId,
            "scnt": scnt,
            "location": completeLocation,
            "statusCode": completeResponse.statusCode,
            "proofEncoding": proofEncoding.rawValue,
            "passwordMode": "sha256_pbkdf2"
        ]
    }

    private class func fetchHashcash(baseURL: URL, widgetKey: String) -> String? {
        guard let url = signinPageURL(baseURL: baseURL, widgetKey: widgetKey) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let result = sendSynchronous(request: request)
        guard let response = result.response else { return nil }

        guard
            let bitsValue = response.value(forHTTPHeaderField: "X-Apple-HC-Bits"),
            let bits = Int(bitsValue),
            bits > 0,
            let challenge = response.value(forHTTPHeaderField: "X-Apple-HC-Challenge"),
            !challenge.isEmpty
        else {
            return nil
        }

        return makeHashcash(challenge: challenge, bits: bits)
    }

    private class func fetchAuthConfiguration() -> [String: Any]? {
        guard let url = URL(string: "https://appstoreconnect.apple.com/olympus/v1/app/config?hostname=itunesconnect.apple.com") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let result = sendSynchronous(request: request)
        guard let response = result.response else { return nil }
        guard response.statusCode < 400 else { return nil }

        return parseJSONDict(data: result.data)
    }

    private class func authEndpointURL(baseURL: URL, pathSuffix: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var basePath = components.path
        if basePath.isEmpty {
            basePath = "/appleauth/auth"
        } else if basePath == "/appleauth" {
            basePath = "/appleauth/auth"
        } else if !basePath.hasSuffix("/auth") {
            basePath += "/auth"
        }

        let normalizedSuffix = pathSuffix.hasPrefix("/") ? String(pathSuffix.dropFirst()) : pathSuffix
        components.path = basePath + "/" + normalizedSuffix
        components.query = nil
        return components.url
    }

    private class func applyFastlaneSharedHeaders(request: inout URLRequest, widgetKey: String) {
        request.setValue("application/json, text/javascript", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(widgetKey, forHTTPHeaderField: "X-Apple-Widget-Key")
    }

    private class func signinPageURL(baseURL: URL, widgetKey: String) -> URL? {
        guard let hashcashBaseURL = authEndpointURL(baseURL: baseURL, pathSuffix: "signin") else { return nil }
        guard var components = URLComponents(url: hashcashBaseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "widgetKey", value: widgetKey)]
        return components.url
    }

    // Mirrors fastlane's cookie workaround for DES values that must be quoted.
    private class func modifiedCookieHeader(for url: URL) -> String? {
        let cookieStorage = HTTPCookieStorage.shared
        guard let cookies = cookieStorage.cookies(for: url), !cookies.isEmpty else {
            return nil
        }
        guard var cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], !cookieHeader.isEmpty else {
            return nil
        }

        for cookie in cookies where cookie.name.contains("DES") {
            let unescapedCookie = "\(cookie.name)=\(cookie.value)"
            let escapedCookie = "\(cookie.name)=\"\(cookie.value)\""
            cookieHeader = cookieHeader.replacingOccurrences(of: unescapedCookie, with: escapedCookie)
        }
        return cookieHeader
    }

    private class func decodeSRPData(_ value: String) -> Data? {
        if let base64 = Data(base64Encoded: value) {
            return base64
        }

        let hex = value.evenLengthLowercasedHex
        if hex.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil {
            return hex.hexData
        }
        return nil
    }

    private class func makeHashcash(challenge: String, bits: Int) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let date = formatter.string(from: Date())

        let fullZeroBytes = bits / 8
        let remainingBits = bits % 8

        for counter in 0...1_000_000 {
            let stamp = "1:\(bits):\(date):\(challenge)::\(counter)"
            let digestBytes = Data(Insecure.SHA1.hash(data: Data(stamp.utf8)))
            var satisfied = true

            for index in 0..<fullZeroBytes {
                if digestBytes[index] != 0 {
                    satisfied = false
                    break
                }
            }

            if satisfied && remainingBits > 0 {
                if fullZeroBytes >= digestBytes.count {
                    continue
                }
                let nextByte = digestBytes[fullZeroBytes]
                let shift = 8 - remainingBits
                let mask = UInt8((0xFF << shift) & 0xFF)
                if (nextByte & mask) != 0 {
                    satisfied = false
                }
            }

            if satisfied {
                return stamp
            }
        }
        return nil
    }

    private class func sendSynchronous(request: URLRequest) -> (data: Data?, response: HTTPURLResponse?) {
        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultResponse: HTTPURLResponse?

        URLSession.shared.dataTask(with: request) { data, response, _ in
            resultData = data
            resultResponse = response as? HTTPURLResponse
            semaphore.signal()
        }.resume()

        semaphore.wait()
        return (resultData, resultResponse)
    }

    private class func parseJSONDict(data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    private class func sha256Data(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    private class func pbkdf2(password: String, saltData: Data, rounds: Int) -> Data? {
        guard let passwordData = password.data(using: .utf8) else { return nil }
        let hashedPasswordData = sha256Data(passwordData)

        var derivedKeyData = Data(repeating: 0, count: 32)
        let derivedCount = derivedKeyData.count
        let status = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes -> Int32 in
            guard let derivedBase = derivedKeyBytes.baseAddress else { return Int32(kCCParamError) }
            return saltData.withUnsafeBytes { saltBytes -> Int32 in
                guard let saltBase = saltBytes.baseAddress else { return Int32(kCCParamError) }
                return hashedPasswordData.withUnsafeBytes { passwordBytes -> Int32 in
                    guard let passwordBase = passwordBytes.baseAddress else { return Int32(kCCParamError) }
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBase.assumingMemoryBound(to: Int8.self),
                        hashedPasswordData.count,
                        saltBase.assumingMemoryBound(to: UInt8.self),
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        derivedBase.assumingMemoryBound(to: UInt8.self),
                        derivedCount
                    )
                }
            }
        }
        return status == kCCSuccess ? derivedKeyData : nil
    }
}

private extension String {
    var utf8Data: Data {
        Data(utf8)
    }

    var evenLengthLowercasedHex: String {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.count.isMultiple(of: 2) ? normalized : "0" + normalized
    }

    var hexData: Data {
        let hex = evenLengthLowercasedHex
        guard !hex.isEmpty else { return Data() }

        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            let bytes = hex[index..<next]
            let value = UInt8(bytes, radix: 16) ?? 0
            data.append(value)
            index = next
        }
        return data
    }
}
