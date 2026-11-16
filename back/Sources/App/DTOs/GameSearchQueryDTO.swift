import Vapor

struct GameSearchQuery: Decodable {
    let q: String?
    let players: String?
    let maxDuration: String?
}