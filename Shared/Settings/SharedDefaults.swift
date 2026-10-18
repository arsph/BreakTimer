import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case dark, light, system

    var id: String { rawValue }

    /// nil follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .dark: "Dunkel"
        case .light: "Hell"
        case .system: "System"
        }
    }
}

/// Small settings in the App Group's UserDefaults, readable from the app and the widget extension.
enum SharedDefaults {
    enum Key {
        static let dailyBudgetMinutes = "dailyBudgetMinutes"
        static let budgetUpdatedAt = "budgetUpdatedAt"
        static let appearance = "appearance"
        static let verboseLogging = "verboseLogging"
        static let notifyLowBudget = "notifyLowBudget"
        static let notifyBudgetUsedUp = "notifyBudgetUsedUp"
        static let askedForNotifications = "askedForNotifications"
        static let lastSuccessfulSync = "lastSuccessfulSync"
        static let budgetSyncedAt = "budgetSyncedAt"
        static let signedInUserID = "signedInUserID"
        static let lastUserID = "lastUserID"
    }

    private static var defaults: UserDefaults { AppGroup.defaults }

    static var dailyBudgetMinutes: Int {
        get {
            let stored = defaults.integer(forKey: Key.dailyBudgetMinutes)
            return stored == 0 ? BudgetRules.defaultMinutes : BudgetRules.clamp(stored)
        }
        set { defaults.set(BudgetRules.clamp(newValue), forKey: Key.dailyBudgetMinutes) }
    }

    /// When the budget setting last changed (for "latest updated_at wins" sync).
    static var budgetUpdatedAt: Date? {
        get { defaults.object(forKey: Key.budgetUpdatedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.budgetUpdatedAt) }
    }

    /// Dark by default.
    static var appearance: AppAppearance {
        get { defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .dark }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    static var verboseLogging: Bool {
        get { defaults.bool(forKey: Key.verboseLogging) }
        set { defaults.set(newValue, forKey: Key.verboseLogging) }
    }

    static var notifyLowBudget: Bool {
        get { defaults.object(forKey: Key.notifyLowBudget) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notifyLowBudget) }
    }

    static var notifyBudgetUsedUp: Bool {
        get { defaults.object(forKey: Key.notifyBudgetUsedUp) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notifyBudgetUsedUp) }
    }

    static var askedForNotifications: Bool {
        get { defaults.bool(forKey: Key.askedForNotifications) }
        set { defaults.set(newValue, forKey: Key.askedForNotifications) }
    }

    static var lastSuccessfulSync: Date? {
        get { defaults.object(forKey: Key.lastSuccessfulSync) as? Date }
        set { defaults.set(newValue, forKey: Key.lastSuccessfulSync) }
    }

    /// `budgetUpdatedAt` of the budget value last pushed to or pulled from Supabase.
    static var budgetSyncedAt: Date? {
        get { defaults.object(forKey: Key.budgetSyncedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.budgetSyncedAt) }
    }

    static var budgetNeedsSync: Bool {
        guard let updated = budgetUpdatedAt else { return false }
        return budgetSyncedAt.map { $0 < updated } ?? true
    }

    /// Supabase user ID while signed in (not secret). Widgets and intents only act while it's set.
    static var signedInUserID: String? {
        get { defaults.string(forKey: Key.signedInUserID) }
        set { defaults.set(newValue, forKey: Key.signedInUserID) }
    }

    /// The user the local data belongs to; survives an unexpected session loss so a different
    /// user signing in next doesn't inherit someone else's breaks.
    static var lastUserID: String? {
        get { defaults.string(forKey: Key.lastUserID) }
        set { defaults.set(newValue, forKey: Key.lastUserID) }
    }

    /// Clears every setting (sign-out / account deletion). Logs are handled separately.
    static func reset() {
        for key in [
            Key.dailyBudgetMinutes, Key.budgetUpdatedAt, Key.appearance, Key.verboseLogging,
            Key.notifyLowBudget, Key.notifyBudgetUsedUp, Key.askedForNotifications, Key.lastSuccessfulSync,
            Key.budgetSyncedAt, Key.signedInUserID, Key.lastUserID,
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
