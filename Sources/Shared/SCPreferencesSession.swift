import Foundation

/// Thin wrapper over the SCPreferences C API.
///
/// The iOS SDK headers mark SCPreferences as unavailable, but the symbols ship
/// in the iOS SystemConfiguration binary, so they are resolved at runtime.
/// Sessions are created with `kSCPreferencesUseEntitlementAuthorization`, so
/// configd's helper performs writes on behalf of any process holding the
/// `com.apple.SystemConfiguration.SCPreferences-write-access` entitlement.
final class SCPreferencesSession {
    enum Failure: LocalizedError {
        case unavailable(String)
        case call(String, Int32, String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let symbol):
                return "SystemConfiguration symbol \(symbol) not found"
            case .call(let fn, let code, let message):
                return "\(fn) failed (\(code)): \(message)"
            }
        }
    }

    private struct API {
        typealias Create = @convention(c) (CFAllocator?, CFString, CFString?, UnsafeRawPointer?) -> Unmanaged<CFTypeRef>?
        typealias GetValue = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
        typealias PathSetValue = @convention(c) (CFTypeRef, CFString, CFDictionary) -> UInt8
        typealias Lock = @convention(c) (CFTypeRef, UInt8) -> UInt8
        typealias Simple = @convention(c) (CFTypeRef) -> UInt8
        typealias ErrorCode = @convention(c) () -> Int32
        typealias ErrorString = @convention(c) (Int32) -> UnsafePointer<CChar>?

        let create: Create
        let entitlementAuthorization: UnsafeRawPointer?
        let getValue: GetValue
        let pathSetValue: PathSetValue
        let lock: Lock
        let unlock: Simple
        let commit: Simple
        let apply: Simple
        let error: ErrorCode
        let errorString: ErrorString

        static let shared: Result<API, Failure> = {
            let handle = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_NOW)
            func sym<T>(_ name: String, _: T.Type) throws -> T {
                guard let handle, let pointer = dlsym(handle, name) else { throw Failure.unavailable(name) }
                return unsafeBitCast(pointer, to: T.self)
            }
            do {
                return .success(API(
                    create: try sym("SCPreferencesCreateWithAuthorization", Create.self),
                    entitlementAuthorization: try sym("kSCPreferencesUseEntitlementAuthorization", UnsafeRawPointer.self)
                        .load(as: UnsafeRawPointer?.self),
                    getValue: try sym("SCPreferencesGetValue", GetValue.self),
                    pathSetValue: try sym("SCPreferencesPathSetValue", PathSetValue.self),
                    lock: try sym("SCPreferencesLock", Lock.self),
                    unlock: try sym("SCPreferencesUnlock", Simple.self),
                    commit: try sym("SCPreferencesCommitChanges", Simple.self),
                    apply: try sym("SCPreferencesApplyChanges", Simple.self),
                    error: try sym("SCError", ErrorCode.self),
                    errorString: try sym("SCErrorString", ErrorString.self)
                ))
            } catch let failure as Failure {
                return .failure(failure)
            } catch {
                return .failure(.unavailable("\(error)"))
            }
        }()
    }

    private let api: API
    private let ref: CFTypeRef

    init(name: String) throws {
        api = try API.shared.get()
        guard let ref = api.create(nil, name as CFString, nil, api.entitlementAuthorization)?.takeRetainedValue() else {
            throw Self.lastError(api, "SCPreferencesCreateWithAuthorization")
        }
        self.ref = ref
    }

    func value(_ key: String) -> Any? {
        api.getValue(ref, key as CFString)?.takeUnretainedValue()
    }

    func setValue(_ dictionary: [String: Any], atPath path: String) throws {
        try check(api.pathSetValue(ref, path as CFString, dictionary as CFDictionary), "SCPreferencesPathSetValue")
    }

    func lock() throws { try check(api.lock(ref, 1), "SCPreferencesLock") }
    func unlock() { _ = api.unlock(ref) }
    func commit() throws { try check(api.commit(ref), "SCPreferencesCommitChanges") }
    func apply() throws { try check(api.apply(ref), "SCPreferencesApplyChanges") }

    private func check(_ ok: UInt8, _ fn: String) throws {
        if ok == 0 { throw Self.lastError(api, fn) }
    }

    private static func lastError(_ api: API, _ fn: String) -> Failure {
        let code = api.error()
        let message = api.errorString(code).map { String(cString: $0) } ?? "unknown error"
        return .call(fn, code, message)
    }
}
