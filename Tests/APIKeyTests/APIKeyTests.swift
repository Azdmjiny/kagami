import XCTest
import Security
import LocalAuthentication
@testable import Kagami

final class APIKeyTests: XCTestCase {
    @MainActor
    func testRenderingDoesNotReadSecret() throws {
        let (store, keychain, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.preferences.modelName = ""
        store.preferences.cloudEnabled = true
        store.preferences.cloudModelName = "test-model"
        store.input = "test"
        for _ in 0..<5 {
            _ = store.hasAvailableModel
            _ = store.canTranslate
            _ = store.hasStoredAPIKey
        }
        XCTAssertEqual(keychain.readCount, 0, "Rendering must not trigger Keychain authorization")
    }

    @MainActor
    func testSuccessfulAuthorizationIsReused() throws {
        let (store, keychain, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(try store.loadAPIKey(), "fake-test-key")
        XCTAssertEqual(try store.loadAPIKey(), "fake-test-key")
        XCTAssertEqual(keychain.readCount, 1, "Reuse successful authorization within this app session")
    }

    @MainActor
    func testFailedAuthorizationCanBeRetriedAndNeverFallsBackSilently() async throws {
        let (store, keychain, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        keychain.failure = .configuration("Keychain authorization canceled")
        store.preferences.cloudEnabled = true
        store.preferences.cloudModelName = "test-model"
        store.input = "test"
        await store.translate()
        XCTAssertEqual(store.error, keychain.failure)
        XCTAssertTrue(store.translation.isEmpty)
        keychain.failure = nil
        XCTAssertEqual(try store.loadAPIKey(), "fake-test-key")
        XCTAssertEqual(keychain.readCount, 2)
    }

    @MainActor
    func testSaveAndDeleteOnlyChangeStateAfterSuccess() throws {
        let (store, keychain, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = try store.loadAPIKey()
        keychain.failure = .configuration("Keychain denied")
        XCTAssertFalse(store.updateAPIKey(""))
        XCTAssertTrue(store.hasStoredAPIKey)
        XCTAssertEqual(try store.loadAPIKey(), "fake-test-key")
        keychain.failure = nil
        XCTAssertTrue(store.updateAPIKey("  replacement-test-key\n"))
        XCTAssertEqual(keychain.key, "replacement-test-key")
        XCTAssertEqual(try store.loadAPIKey(), "replacement-test-key")
        XCTAssertEqual(keychain.readCount, 1)
        XCTAssertTrue(store.updateAPIKey(""))
        XCTAssertFalse(store.hasStoredAPIKey)
        XCTAssertEqual(try store.loadAPIKey(), "")
    }

    func testSecurityStatusesAreNotMistakenForMissingKeys() throws {
        let access = FakeSecurity()
        let keychain = APIKeyStore(access: access)
        access.status = errSecItemNotFound
        XCTAssertNil(try keychain.load())
        XCTAssertFalse(try keychain.containsKey())
        for status in [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed] {
            access.status = status
            XCTAssertThrowsError(try keychain.load()) { error in
                XCTAssertTrue(error.localizedDescription.contains(String(status)))
            }
            XCTAssertThrowsError(try keychain.save(""))
            XCTAssertThrowsError(try keychain.save("test"))
        }
        access.status = errSecSuccess
        XCTAssertEqual(try keychain.load(), "fake-test-key")
        XCTAssertTrue(try keychain.containsKey())
        XCTAssertNil(access.lastQuery[kSecReturnData as String])
        XCTAssertEqual(access.lastQuery[kSecReturnAttributes as String] as? Bool, true)
        XCTAssertEqual((access.lastQuery[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed, true)
        access.status = errSecItemNotFound
        access.addStatus = errSecAuthFailed
        XCTAssertThrowsError(try keychain.save("test"))
        access.addStatus = errSecSuccess
        XCTAssertNoThrow(try keychain.save("test"))
    }

    @MainActor
    private func makeStore() -> (KagamiStore, CountingKeychain, UserDefaults, String) {
        let suite = "KagamiKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = CountingKeychain()
        return (KagamiStore(apiKeyStore: keychain, preferences: .init(defaults: defaults)), keychain, defaults, suite)
    }
}

// Tests access this synchronous fake only from the main actor.
private final class CountingKeychain: APIKeyStoring, @unchecked Sendable {
    var readCount = 0
    var key = "fake-test-key"
    var failure: KagamiError?
    func load() throws -> String? {
        readCount += 1
        if let failure { throw failure }
        return key.isEmpty ? nil : key
    }
    func containsKey() -> Bool { !key.isEmpty }
    func save(_ key: String) throws {
        if let failure { throw failure }
        self.key = key
    }
}

private final class FakeSecurity: KeychainAccess, @unchecked Sendable {
    var status: OSStatus = errSecSuccess
    var addStatus: OSStatus = errSecSuccess
    var lastQuery: [String: Any] = [:]
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        lastQuery = query as! [String: Any]
        result?.pointee = Data("fake-test-key".utf8) as CFData
        return status
    }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus { status }
    func add(_ attributes: CFDictionary) -> OSStatus { addStatus }
    func delete(_ query: CFDictionary) -> OSStatus { status }
}
