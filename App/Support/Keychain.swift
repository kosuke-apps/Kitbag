import Foundation
import Security

/// A small wrapper over the keychain for secrets such as a calendar feed's address, which anyone who has it can read.
enum Keychain {
  private static let service = "dev.kosuke.kitbag.subscriptions"

  private static func query(_ account: String) -> [CFString: Any] {
    [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
  }

  /// Returns whether the item was stored.
  @discardableResult
  static func set(_ value: String, for account: String) -> Bool {
    delete(account)
    var attributes = query(account)
    attributes[kSecValueData] = Data(value.utf8)
    attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  static func get(_ account: String) -> String? {
    var lookup = query(account)
    lookup[kSecReturnData] = true
    lookup[kSecMatchLimit] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func delete(_ account: String) {
    SecItemDelete(query(account) as CFDictionary)
  }
}
