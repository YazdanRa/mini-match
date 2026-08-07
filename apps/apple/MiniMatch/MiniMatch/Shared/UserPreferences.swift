import Foundation
import Observation
import UserNotifications

extension ProcessInfo {
    var isMiniMatchPreviewLaunch: Bool {
        #if DEBUG
        environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || arguments.contains { $0.hasPrefix("--preview-") }
        #else
        false
        #endif
    }
}

enum UserPreference: String, CaseIterable {
    case soundEffectsEnabled
    case dailyReminderEnabled

    var defaultValue: Bool {
        switch self {
        case .soundEffectsEnabled: true
        case .dailyReminderEnabled: false
        }
    }
}

protocol BooleanPreferenceStoring: AnyObject {
    func storedBool(forKey key: String) -> Bool?
    func setStoredBool(_ value: Bool, forKey key: String)
    func removeStoredValue(forKey key: String)
    func synchronizePreferences() -> Bool
}

extension UserDefaults: BooleanPreferenceStoring {
    func storedBool(forKey key: String) -> Bool? {
        object(forKey: key) as? Bool
    }

    func setStoredBool(_ value: Bool, forKey key: String) {
        set(value, forKey: key)
    }

    func removeStoredValue(forKey key: String) {
        removeObject(forKey: key)
    }

    func synchronizePreferences() -> Bool { true }
}

extension NSUbiquitousKeyValueStore: BooleanPreferenceStoring {
    func storedBool(forKey key: String) -> Bool? {
        object(forKey: key) as? Bool
    }

    func setStoredBool(_ value: Bool, forKey key: String) {
        set(value, forKey: key)
    }

    func removeStoredValue(forKey key: String) {
        removeObject(forKey: key)
    }

    func synchronizePreferences() -> Bool {
        synchronize()
    }
}

@MainActor
@Observable
final class UserPreferences {
    private(set) var soundEffectsEnabled: Bool
    private(set) var dailyReminderEnabled: Bool

    @ObservationIgnored private let localStore: any BooleanPreferenceStoring
    @ObservationIgnored private let cloudStore: any BooleanPreferenceStoring
    @ObservationIgnored private var cloudObserver: NSObjectProtocol?

    init(
        localStore: any BooleanPreferenceStoring = UserDefaults.standard,
        cloudStore: any BooleanPreferenceStoring = NSUbiquitousKeyValueStore.default
    ) {
        self.localStore = localStore
        self.cloudStore = cloudStore
        soundEffectsEnabled = localStore.storedBool(
            forKey: UserPreference.soundEffectsEnabled.rawValue
        ) ?? UserPreference.soundEffectsEnabled.defaultValue
        dailyReminderEnabled = localStore.storedBool(
            forKey: UserPreference.dailyReminderEnabled.rawValue
        ) ?? UserPreference.dailyReminderEnabled.defaultValue
    }

    static func preview() -> UserPreferences {
        let store = PreviewPreferenceStore()
        return UserPreferences(localStore: store, cloudStore: store)
    }

    func start() {
        guard cloudObserver == nil else { return }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey]
                as? [String]
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey]
                as? Int
            Task { @MainActor [weak self, changedKeys, reason] in
                self?.applyCloudChanges(changedKeys: changedKeys, reason: reason)
            }
        }
        synchronize()
    }

    func synchronize() {
        _ = cloudStore.synchronizePreferences()
        for preference in UserPreference.allCases {
            if let cloudValue = cloudStore.storedBool(forKey: preference.rawValue) {
                apply(cloudValue, for: preference)
            }
        }
    }

    func applyCloudChanges(
        changedKeys: [String]?,
        reason: Int? = NSUbiquitousKeyValueStoreServerChange
    ) {
        let preferences = reason == NSUbiquitousKeyValueStoreInitialSyncChange
            ? UserPreference.allCases
            : changedKeys?.compactMap(UserPreference.init(rawValue:))
                ?? UserPreference.allCases
        let resetsMissingValues = reason == NSUbiquitousKeyValueStoreServerChange
            || reason == NSUbiquitousKeyValueStoreAccountChange

        for preference in preferences {
            if let cloudValue = cloudStore.storedBool(forKey: preference.rawValue) {
                apply(cloudValue, for: preference)
            } else if resetsMissingValues {
                localStore.removeStoredValue(forKey: preference.rawValue)
                setLocalValue(preference.defaultValue, for: preference)
            }
        }
    }

    func setSoundEffectsEnabled(_ isEnabled: Bool) {
        set(isEnabled, for: .soundEffectsEnabled)
    }

    func setDailyReminderEnabled(_ isEnabled: Bool) {
        set(isEnabled, for: .dailyReminderEnabled)
    }

    private func set(_ value: Bool, for preference: UserPreference) {
        apply(value, for: preference)
        cloudStore.setStoredBool(value, forKey: preference.rawValue)
    }

    private func apply(_ value: Bool, for preference: UserPreference) {
        localStore.setStoredBool(value, forKey: preference.rawValue)
        setLocalValue(value, for: preference)
    }

    private func setLocalValue(_ value: Bool, for preference: UserPreference) {
        switch preference {
        case .soundEffectsEnabled:
            soundEffectsEnabled = value
        case .dailyReminderEnabled:
            dailyReminderEnabled = value
        }
    }
}

private final class PreviewPreferenceStore: BooleanPreferenceStoring {
    private var values: [String: Bool] = [:]

    func storedBool(forKey key: String) -> Bool? { values[key] }
    func setStoredBool(_ value: Bool, forKey key: String) { values[key] = value }
    func removeStoredValue(forKey key: String) { values.removeValue(forKey: key) }
    func synchronizePreferences() -> Bool { true }
}

@MainActor
enum DailyChallengeReminder {
    static let requestIdentifier = "daily-global-challenge-reminder"
    static let reminderHour = 16
    private static var desiredEnabled = false
    private static var reconciliationGeneration = 0

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            true
        default:
            false
        }
    }

    static func enableOnThisDevice() async throws {
        desiredEnabled = true
        reconciliationGeneration &+= 1
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        let isAllowed: Bool

        if status == .notDetermined {
            isAllowed = try await center.requestAuthorization(options: [.alert, .sound])
        } else {
            isAllowed = isAuthorized(status)
        }

        guard desiredEnabled else { throw CancellationError() }
        guard isAllowed else { throw ReminderError.notificationsDisabled }
        try await center.add(makeRequest())
        guard desiredEnabled else {
            removePendingRequest()
            throw CancellationError()
        }
    }

    static func reconcile(
        isEnabled: Bool,
        statusProvider: @MainActor () async -> UNAuthorizationStatus = {
            await authorizationStatus()
        },
        addRequest: @MainActor (UNNotificationRequest) async throws -> Void = {
            try await UNUserNotificationCenter.current().add($0)
        },
        removeRequest: @MainActor () -> Void = { removePendingRequest() }
    ) async {
        desiredEnabled = isEnabled
        reconciliationGeneration &+= 1
        let generation = reconciliationGeneration
        guard isEnabled else {
            removeRequest()
            return
        }
        let status = await statusProvider()
        guard generation == reconciliationGeneration else { return }
        guard isAuthorized(status) else {
            removeRequest()
            return
        }
        try? await addRequest(makeRequest())
        if !desiredEnabled {
            removeRequest()
        }
    }

    static func disableOnThisDevice() {
        desiredEnabled = false
        reconciliationGeneration &+= 1
        removePendingRequest()
    }

    private static func removePendingRequest() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [requestIdentifier]
        )
    }

    static func makeRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Daily Table is ready")
        content.body = String(localized: "Choose your number for today’s global challenge.")
        content.sound = .default

        return UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: reminderHour, minute: 0),
                repeats: true
            )
        )
    }

    private enum ReminderError: Error {
        case notificationsDisabled
    }
}
