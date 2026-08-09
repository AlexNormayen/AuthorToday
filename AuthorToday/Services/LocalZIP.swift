import Foundation
import zlib

/// Minimal ZIP reader for EPUB (stored + deflate), via central directory.
enum LocalZIP {
    struct Entry {
        let path: String
        let data: Data
    }

    static func entries(from url: URL) throws -> [Entry] {
        try entries(from: Data(contentsOf: url))
    }

    static func entries(from data: Data) throws -> [Entry] {
        guard let eocd = findEOCD(in: data) else { throw LocalBookImportError.invalidZIP }
        let cdOffset = Int(readUInt32(data, eocd + 16))
        let entriesCount = Int(readUInt16(data, eocd + 10))
        var result: [Entry] = []
        var offset = cdOffset

        for _ in 0..<entriesCount {
            guard offset + 46 <= data.count, readUInt32(data, offset) == 0x02014b50 else { break }
            let method = Int(readUInt16(data, offset + 10))
            let compSize = Int(readUInt32(data, offset + 20))
            let nameLen = Int(readUInt16(data, offset + 28))
            let extraLen = Int(readUInt16(data, offset + 30))
            let commentLen = Int(readUInt16(data, offset + 32))
            let localHeaderOffset = Int(readUInt32(data, offset + 42))

            let nameStart = offset + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd <= data.count else { break }
            let nameData = data.subdata(in: nameStart..<nameEnd)
            let path = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? "entry-\(offset)"

            offset = nameEnd + extraLen + commentLen
            if path.hasSuffix("/") { continue }

            guard localHeaderOffset + 30 <= data.count,
                  readUInt32(data, localHeaderOffset) == 0x04034b50 else {
                continue
            }
            let localNameLen = Int(readUInt16(data, localHeaderOffset + 26))
            let localExtraLen = Int(readUInt16(data, localHeaderOffset + 28))
            let payloadStart = localHeaderOffset + 30 + localNameLen + localExtraLen
            let payloadEnd = payloadStart + compSize
            guard payloadEnd <= data.count else { continue }
            let compressed = data.subdata(in: payloadStart..<payloadEnd)

            let decoded: Data
            switch method {
            case 0:
                decoded = compressed
            case 8:
                decoded = try inflateRaw(compressed)
            default:
                throw LocalBookImportError.unsupportedZIPCompression(method)
            }
            result.append(Entry(path: path, data: decoded))
        }

        if result.isEmpty { throw LocalBookImportError.invalidZIP }
        return result
    }

    private static func findEOCD(in data: Data) -> Int? {
        // EOCD is at the end; comment can be up to 64KB.
        let minEOCD = 22
        guard data.count >= minEOCD else { return nil }
        let start = max(0, data.count - minEOCD - 0xFFFF)
        var i = data.count - minEOCD
        while i >= start {
            if readUInt32(data, i) == 0x06054b50 { return i }
            i -= 1
        }
        return nil
    }

    private static func inflateRaw(_ input: Data) throws -> Data {
        var stream = z_stream()
        var status = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw LocalBookImportError.inflateFailed }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunk = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunk)

        try input.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) in
            guard let src = srcRaw.bindMemory(to: UInt8.self).baseAddress else {
                throw LocalBookImportError.inflateFailed
            }
            stream.next_in = UnsafeMutablePointer(mutating: src)
            stream.avail_in = uInt(input.count)

            repeat {
                try buffer.withUnsafeMutableBytes { dstRaw in
                    guard let dst = dstRaw.bindMemory(to: UInt8.self).baseAddress else {
                        throw LocalBookImportError.inflateFailed
                    }
                    stream.next_out = dst
                    stream.avail_out = uInt(chunk)
                    status = inflate(&stream, Z_NO_FLUSH)
                    if status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR {
                        throw LocalBookImportError.inflateFailed
                    }
                    let produced = chunk - Int(stream.avail_out)
                    if produced > 0 {
                        output.append(dst, count: produced)
                    }
                }
            } while status != Z_STREAM_END
        }

        guard !output.isEmpty else { throw LocalBookImportError.inflateFailed }
        return output
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
