import Vapor

struct RegisterDTO: Content {
    let email: String
    let password: String
}

struct LoginDTO: Content {
    let email: String
    let password: String
}

struct AuthUserDTO: Content {
    let id: UUID
    let email: String
    let createdAt: Date?
}

struct AuthResponseDTO: Content {
    let token: String
    let expiresAt: Date
    let user: AuthUserDTO
}
