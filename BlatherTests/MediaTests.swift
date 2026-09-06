import Foundation
import Testing
@testable import Blather

struct MediaTests {
    @Test func kindFromMime() {
        #expect(MediaStore.kind(forMime: "image/png") == .image)
        #expect(MediaStore.kind(forMime: "video/mp4") == .video)
        #expect(MediaStore.kind(forMime: "application/pdf") == nil)
    }

    @Test func importPngAndDelete() throws {
        let db = try AppDatabase.inMemory()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("blather-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        AppPaths.overrideDataDirectory = temp
        defer {
            AppPaths.overrideDataDirectory = nil
            try? FileManager.default.removeItem(at: temp)
        }

        let source = temp.appendingPathComponent("dot.png")
        try tinyPNG().write(to: source)

        let item = try MediaStore.importFile(from: source, into: db)
        #expect(item.kind == .image)
        #expect(item.mimeType == "image/png")
        #expect(item.size > 0)
        let relative = try db.media.pathOf(item.id)
        #expect(relative != nil)
        #expect(FileManager.default.fileExists(atPath: MediaStore.fileURL(for: relative!).path))

        try MediaStore.delete(id: item.id, from: db)
        #expect(try db.media.get(item.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: MediaStore.fileURL(for: relative!).path))
    }

    private func tinyPNG() -> Data {
        Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
    }
}
