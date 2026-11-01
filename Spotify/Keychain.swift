// 앱 타깃 — 키체인 (Spotify 앱 승인 세션 보관, AfterFirstUnlock). 작업 032: 옛 웹 로그인 파일에서 Keychain만 옮김 (동작 그대로)
import Foundation
import Security

enum Keychain {
    static func save(_ value: String, for key: String) {
        saveData(Data(value.utf8), for: key)
    }

    static func read(_ key: String) -> String? {
        readData(key).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// 바이트 그대로 저장 (작업 025 검토 2차: SDK 세션을 NSKeyedArchiver로 바꾼 값)
    static func saveData(_ data: Data, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        // 화면이 잠겨 있어도 읽을 수 있게 (잠금 상태에서 토큰 갱신이 필요하므로)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func readData(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
