import Testing
@testable import C1Core

/// Section 2: the spacer's own commands, `length <pt>` (0-1000, else
/// refused) and `rest` -- parsed once here so vzhelper's stdin handler
/// (I2) never re-implements the range check.
@Suite("SpacerCommandParser")
struct SpacerCommandParserTests {
    @Test("rest")
    func rest() {
        #expect(SpacerCommandParser.parse("rest") == .success(.rest))
    }

    @Test("length at the low end of the range")
    func lengthZero() {
        #expect(SpacerCommandParser.parse("length 0") == .success(.length(0)))
    }

    @Test("length at the high end of the range")
    func lengthMax() {
        #expect(SpacerCommandParser.parse("length 1000") == .success(.length(1000)))
    }

    @Test("length in the middle of the range")
    func lengthMid() {
        #expect(SpacerCommandParser.parse("length 650.5") == .success(.length(650.5)))
    }

    @Test("length below 0 is refused")
    func lengthBelowRange() {
        #expect(SpacerCommandParser.parse("length -1") == .failure(.outOfRange(-1)))
    }

    @Test("length above 1000 is refused")
    func lengthAboveRange() {
        #expect(SpacerCommandParser.parse("length 1000.1") == .failure(.outOfRange(1000.1)))
    }

    @Test("length with no number is malformed")
    func lengthMissingNumber() {
        #expect(SpacerCommandParser.parse("length") == .failure(.malformed("length")))
    }

    @Test("length with a non-numeric argument is malformed")
    func lengthNotANumber() {
        #expect(SpacerCommandParser.parse("length abc") == .failure(.malformed("length abc")))
    }

    @Test("rest with a trailing argument is malformed")
    func restWithArgument() {
        #expect(SpacerCommandParser.parse("rest now") == .failure(.malformed("rest now")))
    }

    @Test("an unknown command is malformed")
    func unknownCommand() {
        #expect(SpacerCommandParser.parse("jump 5") == .failure(.malformed("jump 5")))
    }

    @Test("an empty line is malformed")
    func emptyLine() {
        #expect(SpacerCommandParser.parse("") == .failure(.malformed("")))
    }
}
