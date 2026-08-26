import Foundation
import ObjectiveC

// MARK: - 语言设置管理

enum AppLanguage: String {
    case system = "system"
    case zhHans = "zh-Hans"
    case english = "en"

    var displayName: String {
        switch self {
        case .system:  return NSLocalizedString("settings_language_system", comment: "")
        case .zhHans:  return NSLocalizedString("settings_language_zh", comment: "")
        case .english: return NSLocalizedString("settings_language_en", comment: "")
        }
    }

    /// 映射到 Bundle 的 .lproj 目录名
    var lprojName: String? {
        switch self {
        case .system:  return nil
        case .zhHans:  return "zh-Hans"
        case .english: return "en"
        }
    }
}

// MARK: - Bundle 语言替换（通过方法交换实现强制本地化）

private var bundleKey: UInt8 = 0

final class BundleLocalized: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        // 替换为强制语言的 bundle 来查找字符串
        if let bundle = objc_getAssociatedObject(self, &bundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// 设置全局强制语言（nil 则跟随系统）
    static func setLanguage(_ langCode: String?) {
        guard let langCode,
              let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            // 跟随系统：取消替换
            object_setClass(Bundle.main, Bundle.self)
            objc_setAssociatedObject(Bundle.main, &bundleKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return
        }
        // 用 BundleLocalized 替换 Bundle.main 的类，让它从目标语言 bundle 取值
        object_setClass(Bundle.main, BundleLocalized.self)
        objc_setAssociatedObject(Bundle.main, &bundleKey, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// 启动时应用语言设置（必须在 UI 渲染前调用，且重启后生效）
func applyAppLanguage() {
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
    if lang == "system" {
        Bundle.setLanguage(nil)
    } else {
        Bundle.setLanguage(lang)
    }
}
