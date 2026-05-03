import Foundation

public struct HostdOutputChunk: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let data: Data

    public init(sequence: UInt64, data: Data) {
        self.sequence = sequence
        self.data = data
    }
}

public struct HostdOutputRead: Codable, Equatable, Sendable {
    public let chunks: [HostdOutputChunk]
    public let nextSequence: UInt64
    public let truncated: Bool
    public let streamEnded: Bool

    public init(chunks: [HostdOutputChunk], nextSequence: UInt64, truncated: Bool, streamEnded: Bool = false) {
        self.chunks = chunks
        self.nextSequence = nextSequence
        self.truncated = truncated
        self.streamEnded = streamEnded
    }

    private enum CodingKeys: String, CodingKey {
        case chunks
        case nextSequence
        case truncated
        case streamEnded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chunks = try container.decode([HostdOutputChunk].self, forKey: .chunks)
        nextSequence = try container.decode(UInt64.self, forKey: .nextSequence)
        truncated = try container.decode(Bool.self, forKey: .truncated)
        streamEnded = try container.decodeIfPresent(Bool.self, forKey: .streamEnded) ?? false
    }
}

public struct HostdOutputRingBuffer: Sendable {
    private let limit: Int
    private var bytes = Data()
    private var startSequence: UInt64 = 0
    private var endSequence: UInt64 = 0

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    public var nextSequence: UInt64 {
        endSequence
    }

    public mutating func append(_ data: Data) {
        guard !data.isEmpty else { return }
        bytes.append(data)
        endSequence += UInt64(data.count)
        trim()
    }

    public func read(after sequence: UInt64?, limit: Int? = nil) -> HostdOutputRead {
        let requested = sequence ?? startSequence
        var effective = max(requested, startSequence)
        let truncated = requested < startSequence
        guard effective < endSequence else {
            return HostdOutputRead(chunks: [], nextSequence: endSequence, truncated: truncated)
        }
        var wasTruncated = truncated
        if let limit {
            let maximumBytes = max(0, limit)
            let availableBytes = Int(endSequence - effective)
            if availableBytes > maximumBytes {
                effective = endSequence - UInt64(maximumBytes)
                wasTruncated = true
            }
        }
        guard effective < endSequence else {
            return HostdOutputRead(chunks: [], nextSequence: endSequence, truncated: wasTruncated)
        }
        let offset = Int(effective - startSequence)
        let index = bytes.index(bytes.startIndex, offsetBy: offset)
        return HostdOutputRead(
            chunks: [HostdOutputChunk(sequence: effective, data: Data(bytes.suffix(from: index)))],
            nextSequence: endSequence,
            truncated: wasTruncated
        )
    }

    private mutating func trim() {
        guard bytes.count > limit else { return }
        let dropCount = bytes.count - limit
        bytes.removeFirst(dropCount)
        startSequence += UInt64(dropCount)
    }
}
