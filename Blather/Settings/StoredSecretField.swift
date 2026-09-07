import SwiftUI

/// Masked secret shown in a `SecureField` when a value is already stored.
/// The real secret is never placed in the field; a random-length dummy string
/// stands in until the user starts typing a replacement.
enum StoredSecretMask {
    static let dummyScalar: Character = "\u{E000}"
    static let dummyLengthRange = 10...18

    static func makeDummy(length: Int = Int.random(in: dummyLengthRange)) -> String {
        String(repeating: dummyScalar, count: max(dummyLengthRange.lowerBound, length))
    }

    /// Maps a field edit onto the value that should be saved.
    /// An empty result means "keep the stored secret".
    static func committedValue(dummy: String, newValue: String) -> String {
        if newValue == dummy { return "" }
        if newValue.hasPrefix(dummy) {
            return String(newValue.dropFirst(dummy.count))
        }
        if !newValue.isEmpty, newValue.allSatisfy({ $0 == dummyScalar }) {
            return ""
        }
        return newValue.filter { $0 != dummyScalar }
    }
}

struct StoredSecretField: View {
    let title: String
    let hasStoredSecret: Bool
    @Binding var text: String

    @State private var fieldText = ""
    @State private var dummyValue: String?

    init(_ title: String, text: Binding<String>, hasStoredSecret: Bool) {
        self.title = title
        self.hasStoredSecret = hasStoredSecret
        self._text = text
    }

    var body: some View {
        SecureField(title, text: $fieldText)
            .onAppear(perform: syncFromStored)
            .onChange(of: hasStoredSecret) { _, _ in
                syncFromStored()
            }
            .onChange(of: text) { _, new in
                if new.isEmpty {
                    syncFromStored()
                }
            }
            .onChange(of: fieldText) { _, new in
                handleFieldChange(new)
            }
    }

    private func syncFromStored() {
        if hasStoredSecret, text.isEmpty {
            guard dummyValue == nil else { return }
            let dummy = StoredSecretMask.makeDummy()
            dummyValue = dummy
            fieldText = dummy
        } else if dummyValue != nil, !hasStoredSecret {
            dummyValue = nil
            fieldText = text
        } else if !hasStoredSecret, fieldText != text {
            dummyValue = nil
            fieldText = text
        }
    }

    private func handleFieldChange(_ new: String) {
        guard let dummy = dummyValue else {
            if text != new {
                text = new
            }
            return
        }
        guard new != dummy else { return }
        let committed = StoredSecretMask.committedValue(dummy: dummy, newValue: new)
        dummyValue = nil
        if fieldText != committed {
            fieldText = committed
        }
        if text != committed {
            text = committed
        }
    }
}
