import ApplicationServices

/// Every `AXError` case to its Swift case name, so the rest of this package
/// (and IceCore's `ReadClassifier`, which never imports ApplicationServices
/// itself) can compare and log Accessibility errors as plain strings. Unknown
/// raw values name themselves rather than being dropped, which matters for a
/// census log: a code this table has never seen should be visible, not
/// silently folded into some existing case.
public enum AXErrorNames {
    public static func name(_ error: AXError) -> String {
        switch error {
        case .success: return "success"
        case .failure: return "failure"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .invalidUIElementObserver: return "invalidUIElementObserver"
        case .cannotComplete: return "cannotComplete"
        case .attributeUnsupported: return "attributeUnsupported"
        case .actionUnsupported: return "actionUnsupported"
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented: return "notImplemented"
        case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
        case .notificationNotRegistered: return "notificationNotRegistered"
        case .apiDisabled: return "apiDisabled"
        case .noValue: return "noValue"
        case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: return "notEnoughPrecision"
        default: return "unknown(\(error.rawValue))"
        }
    }
}
