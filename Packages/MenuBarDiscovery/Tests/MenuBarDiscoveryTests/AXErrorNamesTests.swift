import ApplicationServices
import Testing
@testable import MenuBarDiscovery

/// Every `AXError` case to its Swift case name (plan section 4.2), plus the
/// unknown-raw-value fallback IceCore's `ReadClassifier` never has to see
/// (any string not in its harmless set already fails a read; naming the raw
/// value just keeps a census log readable).
@Suite("AXErrorNames")
struct AXErrorNamesTests {
    @Test("every named AXError case", arguments: [
        (AXError.success, "success"),
        (AXError.failure, "failure"),
        (AXError.illegalArgument, "illegalArgument"),
        (AXError.invalidUIElement, "invalidUIElement"),
        (AXError.invalidUIElementObserver, "invalidUIElementObserver"),
        (AXError.cannotComplete, "cannotComplete"),
        (AXError.attributeUnsupported, "attributeUnsupported"),
        (AXError.actionUnsupported, "actionUnsupported"),
        (AXError.notificationUnsupported, "notificationUnsupported"),
        (AXError.notImplemented, "notImplemented"),
        (AXError.notificationAlreadyRegistered, "notificationAlreadyRegistered"),
        (AXError.notificationNotRegistered, "notificationNotRegistered"),
        (AXError.apiDisabled, "apiDisabled"),
        (AXError.noValue, "noValue"),
        (AXError.parameterizedAttributeUnsupported, "parameterizedAttributeUnsupported"),
        (AXError.notEnoughPrecision, "notEnoughPrecision"),
    ])
    func namedCase(error: AXError, expected: String) {
        #expect(AXErrorNames.name(error) == expected)
    }

    @Test("an unrecognised raw value names itself with its raw value")
    func unknownRawValue() {
        let unknown = AXError(rawValue: 424_242)!
        #expect(AXErrorNames.name(unknown) == "unknown(424242)")
    }

    @Test("a negative, still-unrecognised raw value also names itself")
    func unknownNegativeRawValue() {
        let unknown = AXError(rawValue: -1)!
        #expect(AXErrorNames.name(unknown) == "unknown(-1)")
    }
}
