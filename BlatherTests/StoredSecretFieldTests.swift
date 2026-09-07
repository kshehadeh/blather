import Foundation
import Testing
@testable import Blather

struct StoredSecretFieldTests {
    @Test func dummyLengthIsRandomWithinRange() {
        let lengths = (0..<40).map { _ in StoredSecretMask.makeDummy().count }
        #expect(lengths.allSatisfy { StoredSecretMask.dummyLengthRange.contains($0) })
        #expect(Set(lengths).count > 1)
    }

    @Test func dummyUsesSentinelCharacters() {
        let dummy = StoredSecretMask.makeDummy(length: 12)
        #expect(dummy.count == 12)
        #expect(dummy.allSatisfy { $0 == StoredSecretMask.dummyScalar })
    }

    @Test func typingAppendsOnlyTheNewCharacters() {
        let dummy = StoredSecretMask.makeDummy(length: 12)
        let committed = StoredSecretMask.committedValue(dummy: dummy, newValue: dummy + "new-secret")
        #expect(committed == "new-secret")
    }

    @Test func replacingTheDummyKeepsTheTypedValue() {
        let dummy = StoredSecretMask.makeDummy(length: 12)
        let committed = StoredSecretMask.committedValue(dummy: dummy, newValue: "typed")
        #expect(committed == "typed")
    }

    @Test func deletingDummyCharactersClearsTheField() {
        let dummy = StoredSecretMask.makeDummy(length: 12)
        let shortened = String(dummy.dropLast())
        let committed = StoredSecretMask.committedValue(dummy: dummy, newValue: shortened)
        #expect(committed.isEmpty)
    }

    @Test func unchangedDummyMeansKeepStoredSecret() {
        let dummy = StoredSecretMask.makeDummy(length: 14)
        let committed = StoredSecretMask.committedValue(dummy: dummy, newValue: dummy)
        #expect(committed.isEmpty)
    }

    @Test func clearingTheFieldMeansKeepStoredSecret() {
        let dummy = StoredSecretMask.makeDummy(length: 10)
        let committed = StoredSecretMask.committedValue(dummy: dummy, newValue: "")
        #expect(committed.isEmpty)
    }
}
