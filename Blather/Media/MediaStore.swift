import AppKit
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MediaImportError: Error, LocalizedError {
    case unsupportedType(String)
    case tooLarge(Int)
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let type):
            return "Unsupported media type: \(type.isEmpty ? "unknown" : type)"
        case .tooLarge(let limit):
            return "File exceeds the \(limit / (1024 * 1024))MB upload limit"
        case .copyFailed:
            return "Could not copy the file into Blather’s media folder"
        }
    }
}

enum MediaStore {
    static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.jpeg, .png, .webP, .gif, .mpeg4Movie, .quickTimeMovie]
        if let webm = UTType(filenameExtension: "webm") {
            types.append(webm)
        }
        return types
    }

    static func kind(forMime mime: String) -> MediaKind? {
        if MediaLimits.imageMimeTypes.contains(mime) { return .image }
        if MediaLimits.videoMimeTypes.contains(mime) { return .video }
        return nil
    }

    static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType
        {
            return mime
        }
        return "application/octet-stream"
    }

    static func importFile(from source: URL, into database: AppDatabase) throws -> MediaItem {
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.stopAccessingSecurityScopedResource() }
        }

        let mime = mimeType(for: source)
        guard let kind = kind(forMime: mime) else {
            throw MediaImportError.unsupportedType(mime)
        }

        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        let size = values.fileSize ?? 0
        if size > MediaLimits.uploadMaxBytes {
            throw MediaImportError.tooLarge(MediaLimits.uploadMaxBytes)
        }

        try AppPaths.ensureDirectories()
        let pathExtension = source.pathExtension.isEmpty
            ? String(defaultExtension(for: mime).dropFirst())
            : source.pathExtension
        let filename = "\(Time.newId()).\(pathExtension)"
        let destination = AppPaths.mediaDirectory.appendingPathComponent(filename)

        try copyCapped(from: source, to: destination, limit: MediaLimits.uploadMaxBytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        var width: Int?
        var height: Int?
        var duration: Double?
        if kind == .image, let size = imageSize(at: destination) {
            width = Int(size.width)
            height = Int(size.height)
        } else if kind == .video, let meta = videoMetadata(at: destination) {
            width = meta.width
            height = meta.height
            duration = meta.duration
        }

        return try database.media.create(
            kind: kind,
            mimeType: mime,
            name: source.lastPathComponent,
            size: (try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? size,
            width: width,
            height: height,
            durationSeconds: duration,
            path: filename
        )
    }

    static func fileURL(for relativePath: String) -> URL {
        AppPaths.mediaDirectory.appendingPathComponent(relativePath)
    }

    static func delete(id: String, from database: AppDatabase) throws {
        if let relative = try database.media.remove(id) {
            try? FileManager.default.removeItem(at: fileURL(for: relative))
        }
    }

    static func thumbnail(for item: MediaItem, relativePath: String, maxSize: CGFloat = 64) -> NSImage? {
        let url = fileURL(for: relativePath)
        if item.kind == .image {
            return NSImage(contentsOf: url)
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize * 2, height: maxSize * 2)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: maxSize, height: maxSize))
    }

    private static func defaultExtension(for mime: String) -> String {
        switch mime {
        case "image/jpeg": return ".jpg"
        case "image/png": return ".png"
        case "image/webp": return ".webp"
        case "image/gif": return ".gif"
        case "video/mp4": return ".mp4"
        case "video/quicktime": return ".mov"
        case "video/webm": return ".webm"
        default: return ""
        }
    }

    private static func copyCapped(from source: URL, to destination: URL, limit: Int) throws {
        guard let input = InputStream(url: source), let output = OutputStream(url: destination, append: false) else {
            throw MediaImportError.copyFailed
        }
        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }
        var written = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while input.hasBytesAvailable {
            let read = input.read(&buffer, maxLength: buffer.count)
            if read < 0 { throw MediaImportError.copyFailed }
            if read == 0 { break }
            written += read
            if written > limit {
                try? FileManager.default.removeItem(at: destination)
                throw MediaImportError.tooLarge(limit)
            }
            let wrote = output.write(buffer, maxLength: read)
            if wrote < 0 { throw MediaImportError.copyFailed }
        }
    }

    private static func imageSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private static func videoMetadata(at url: URL) -> (width: Int, height: Int, duration: Double)? {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        guard let track = asset.tracks(withMediaType: .video).first else {
            return duration.isFinite ? (0, 0, duration) : nil
        }
        let size = track.naturalSize.applying(track.preferredTransform)
        return (Int(abs(size.width)), Int(abs(size.height)), duration)
    }
}
