import Foundation

final class AppSettings: ObservableObject {
    private enum Keys {
        static let prefersRecentFilesOnHome = "app.settings.prefersRecentFilesOnHome"
        static let autoSaveDrafts = "app.settings.autoSaveDrafts"
        static let defaultPreviewMode = "app.settings.defaultPreviewMode"
        static let hasPreparedAppIcon1024 = "app.settings.hasPreparedAppIcon1024"
        static let hasPreparedIPhone61Screenshots = "app.settings.hasPreparedIPhone61Screenshots"
        static let hasPreparedIPhone67Screenshots = "app.settings.hasPreparedIPhone67Screenshots"
        static let hasPreparedPrivacyPolicyURL = "app.settings.hasPreparedPrivacyPolicyURL"
    }

    private let defaults: UserDefaults

    @Published var prefersRecentFilesOnHome: Bool {
        didSet { defaults.set(prefersRecentFilesOnHome, forKey: Keys.prefersRecentFilesOnHome) }
    }

    @Published var autoSaveDrafts: Bool {
        didSet { defaults.set(autoSaveDrafts, forKey: Keys.autoSaveDrafts) }
    }

    @Published var defaultPreviewMode: PreviewMode {
        didSet { defaults.set(defaultPreviewMode.rawValue, forKey: Keys.defaultPreviewMode) }
    }

    @Published var hasPreparedAppIcon1024: Bool {
        didSet { defaults.set(hasPreparedAppIcon1024, forKey: Keys.hasPreparedAppIcon1024) }
    }

    @Published var hasPreparedIPhone61Screenshots: Bool {
        didSet { defaults.set(hasPreparedIPhone61Screenshots, forKey: Keys.hasPreparedIPhone61Screenshots) }
    }

    @Published var hasPreparedIPhone67Screenshots: Bool {
        didSet { defaults.set(hasPreparedIPhone67Screenshots, forKey: Keys.hasPreparedIPhone67Screenshots) }
    }

    @Published var hasPreparedPrivacyPolicyURL: Bool {
        didSet { defaults.set(hasPreparedPrivacyPolicyURL, forKey: Keys.hasPreparedPrivacyPolicyURL) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.prefersRecentFilesOnHome = defaults.object(forKey: Keys.prefersRecentFilesOnHome) as? Bool ?? true
        self.autoSaveDrafts = defaults.object(forKey: Keys.autoSaveDrafts) as? Bool ?? true
        self.defaultPreviewMode = PreviewMode(
            rawValue: defaults.string(forKey: Keys.defaultPreviewMode) ?? PreviewMode.original.rawValue
        ) ?? .original

        self.hasPreparedAppIcon1024 = defaults.bool(forKey: Keys.hasPreparedAppIcon1024)
        self.hasPreparedIPhone61Screenshots = defaults.bool(forKey: Keys.hasPreparedIPhone61Screenshots)
        self.hasPreparedIPhone67Screenshots = defaults.bool(forKey: Keys.hasPreparedIPhone67Screenshots)
        self.hasPreparedPrivacyPolicyURL = defaults.bool(forKey: Keys.hasPreparedPrivacyPolicyURL)
    }
}
