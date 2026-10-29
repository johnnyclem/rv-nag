import Foundation

class Persistence {
    static let shared = Persistence()
    
    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ReviewNagger", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending.json")
    }()
    
    func load() -> [ReviewItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([ReviewItem].self, from: data) else {
            return []
        }
        return items.filter { !$0.acknowledged }
    }
    
    func save(_ items: [ReviewItem]) {
        let active = items.filter { !$0.acknowledged }
        if let data = try? JSONEncoder().encode(active) {
            try? data.write(to: fileURL)
        }
    }
}
