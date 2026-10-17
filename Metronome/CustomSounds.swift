import Foundation

/// A click sound recorded by the user.
struct CustomSound: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var hasDownbeat: Bool
    var sampleRate: Double
}

/// Which click sound is chosen: built in, or recorded. Stored as text so it can be remembered.
enum SoundChoice: Hashable, RawRepresentable {
    case builtIn(ClickSound)
    case custom(UUID)

    init?(rawValue: String) {
        if rawValue.hasPrefix("custom:"), let id = UUID(uuidString: String(rawValue.dropFirst(7))) {
            self = .custom(id)
        } else if let number = Int(rawValue), let sound = ClickSound(rawValue: number) {
            self = .builtIn(sound)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .builtIn(let sound): String(sound.rawValue)
        case .custom(let id): "custom:\(id.uuidString)"
        }
    }
}

/// The user's recorded sounds, kept on the device: a list of names, and each
/// sound's samples in its own files.
@Observable
final class CustomSounds {
    static let limit = 10
    static let maxNameLength = 14

    private(set) var all: [CustomSound] = []
    private var samples: [UUID: (beat: [Float], downbeat: [Float]?)] = [:]

    private let folder = URL.applicationSupportDirectory.appending(path: "CustomSounds", directoryHint: .isDirectory)
    private var listFile: URL { folder.appending(path: "sounds.json") }

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: listFile), let list = try? JSONDecoder().decode([CustomSound].self, from: data) {
            // Skip any whose samples have gone missing.
            all = list.filter { FileManager.default.fileExists(atPath: file(for: $0.id, downbeat: false).path) }
        }
    }

    var isFull: Bool { all.count >= Self.limit }

    func sound(_ id: UUID) -> CustomSound? {
        all.first { $0.id == id }
    }

    /// "CUSTOM 1", or the lowest number not already taken.
    var nextDefaultName: String {
        let names = Set(all.map { $0.name.uppercased() })
        let number = (1...).first { !names.contains("CUSTOM \($0)") }!
        return "CUSTOM \(number)"
    }

    func add(name: String, beat: [Float], downbeat: [Float]?, sampleRate: Double) -> CustomSound {
        let sound = CustomSound(id: UUID(), name: name, hasDownbeat: downbeat != nil, sampleRate: sampleRate)
        write(beat, to: file(for: sound.id, downbeat: false))
        if let downbeat { write(downbeat, to: file(for: sound.id, downbeat: true)) }
        samples[sound.id] = (beat, downbeat)
        all.append(sound)
        saveList()
        return sound
    }

    /// Renames a sound and replaces its recordings.
    func update(_ id: UUID, name: String, beat: [Float], downbeat: [Float]?, sampleRate: Double) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].name = name
        all[index].hasDownbeat = downbeat != nil
        all[index].sampleRate = sampleRate
        write(beat, to: file(for: id, downbeat: false))
        if let downbeat {
            write(downbeat, to: file(for: id, downbeat: true))
        } else {
            try? FileManager.default.removeItem(at: file(for: id, downbeat: true))
        }
        samples[id] = (beat, downbeat)
        saveList()
    }

    func delete(_ id: UUID) {
        all.removeAll { $0.id == id }
        samples[id] = nil
        try? FileManager.default.removeItem(at: file(for: id, downbeat: false))
        try? FileManager.default.removeItem(at: file(for: id, downbeat: true))
        saveList()
    }

    /// A sound's recorded beat and downbeat, read from disk the first time.
    func samples(for id: UUID) -> (beat: [Float], downbeat: [Float]?)? {
        if let cached = samples[id] { return cached }
        guard let sound = sound(id), let beat = read(file(for: id, downbeat: false)) else { return nil }
        let loaded = (beat, sound.hasDownbeat ? read(file(for: id, downbeat: true)) : nil)
        samples[id] = loaded
        return loaded
    }

    private func file(for id: UUID, downbeat: Bool) -> URL {
        folder.appending(path: "\(id.uuidString)-\(downbeat ? "downbeat" : "beat").f32")
    }

    private func saveList() {
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: listFile, options: .atomic) }
    }

    private func write(_ samples: [Float], to url: URL) {
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: url, options: .atomic)
    }

    private func read(_ url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

/// Keeps custom sound names friendly.
enum SoundName {
    /// Silly ideas offered when renaming.
    static let suggestions = [
        "Knee Slap", "Desk Drum", "Bonk", "Spoon Solo", "Tongue Pop", "Boop", "Thwack",
        "Pen Tap", "Kettle Ping", "Cheek Pop", "Big Clap", "Hey!", "Belly Drum", "Mug Tink",
        "Duck Mode", "Clickety", "Bloop", "Snap Attack", "Doink", "Tick Tock Croc",
    ]

    /// Words that are fine on their own but turn up inside innocent ones ("class",
    /// "Scunthorpe"), so only whole words are checked.
    private static let bannedWords: Set<String> = [
        "ass", "arse", "tit", "tits", "cock", "cocks", "dick", "dik", "fag", "fags", "piss", "prick",
        "crap", "damn", "hell", "bum", "poo", "nob", "knob", "sod", "git", "slag", "hoe", "cum",
        "bastard", "bollock", "bollocks", "boob", "boobs", "penis", "vagina", "sex", "porn", "nazi",
        "pussy", "nigger", "niggers", "nigga", "niggas",
    ]

    /// Stems rude wherever they appear.
    private static let bannedStems = [
        "fuck", "fuk", "fck", "shit", "cunt", "bitch", "wank", "twat", "slut", "whore",
        "asshole", "arsehole", "dickhead", "bellend", "retard", "spastic", "motherf", "jizz",
        "dildo", "tosser",
    ]

    /// Whether a name passes the filter, seeing through tricks like "5h1t" or "s.h.i.t".
    static func isFriendly(_ name: String) -> Bool {
        let lookalikes: [Character: Character] = [
            "0": "o", "1": "i", "!": "i", "3": "e", "4": "a", "@": "a", "5": "s", "$": "s", "7": "t", "8": "b",
        ]
        let plain = String(name.lowercased().map { lookalikes[$0] ?? $0 })
        let words = plain.split { !$0.isLetter }.map(String.init)
        if words.contains(where: bannedWords.contains) { return false }
        let squashed = plain.filter(\.isLetter)
        return !bannedStems.contains { squashed.contains($0) }
    }
}

/// A sound packed into a small file to send to someone: name, rate and 16-bit samples.
struct SharedSound: Codable {
    static let fileExtension = "metrosound"
    /// Anything longer than this isn't a click; it's refused on import.
    private static let maxSeconds = 1.0

    let name: String
    let sampleRate: Double
    private let beatData: Data
    private let downbeatData: Data?

    var beat: [Float] { Self.unpack(beatData) }
    var downbeat: [Float]? { downbeatData.map(Self.unpack) }

    init(name: String, beat: [Float], downbeat: [Float]?, sampleRate: Double) {
        self.name = name
        self.sampleRate = sampleRate
        beatData = Self.pack(beat)
        downbeatData = downbeat.map(Self.pack)
    }

    /// Writes it to a temporary file named after the sound, ready to hand to the share sheet.
    func writeFile() throws -> URL {
        let safeName = name.filter { $0.isLetter || $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces)
        let url = URL.temporaryDirectory.appending(path: "\(safeName.isEmpty ? "Sound" : safeName).\(Self.fileExtension)")
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        return url
    }

    /// Reads a shared file, refusing anything that doesn't look like a short click.
    /// The name is tidied up and checked like one typed in the app.
    static func read(from url: URL) -> SharedSound? {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count < 2_000_000,
              let sound = try? JSONDecoder().decode(SharedSound.self, from: data),
              (8_000...192_000).contains(sound.sampleRate),
              !sound.beatData.isEmpty,
              Double(sound.beatData.count / 2) <= sound.sampleRate * maxSeconds,
              Double((sound.downbeatData?.count ?? 0) / 2) <= sound.sampleRate * maxSeconds
        else { return nil }
        var name = String(sound.name.uppercased().prefix(CustomSounds.maxNameLength)).trimmingCharacters(in: .whitespaces)
        if name.isEmpty || !SoundName.isFriendly(name) { name = "SHARED SOUND" }
        return SharedSound(name: name, beat: sound.beat, downbeat: sound.downbeat, sampleRate: sound.sampleRate)
    }

    private static func pack(_ samples: [Float]) -> Data {
        let values = samples.map { Int16(max(-1, min(1, $0)) * Float(Int16.max)).littleEndian }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func unpack(_ data: Data) -> [Float] {
        data.withUnsafeBytes { bytes in
            (0..<bytes.count / 2).map { i in
                Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / Float(Int16.max)
            }
        }
    }
}
