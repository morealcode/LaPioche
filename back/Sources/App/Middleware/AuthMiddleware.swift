import Vapor
import Fluent
import JWT

struct AuthMiddleware: AsyncMiddleware {
    func respond(
        to request: Request,
        chainingTo next: AsyncResponder
    ) async throws -> Response {

        let payload: UserTokenPayload

        // Vérification de la signature et de l'expiration du JWT.
        do {
            payload = try await request.jwt.verify(as: UserTokenPayload.self)
        } catch {
            throw Abort(.unauthorized, reason: "Authentification requise.")
        }

        // Vérification de l'identifiant utilisateur.
        guard let userID = UUID(uuidString: payload.subject.value) else {
            throw Abort(.unauthorized, reason: "Authentification requise.")
        }

        // Vérification que le compte existe toujours en base.
        guard let user = try await User.find(userID, on: request.db) else {
            throw Abort(.unauthorized, reason: "Authentification requise.")
        }

        request.auth.login(user)

        return try await next.respond(to: request)
    }
}
