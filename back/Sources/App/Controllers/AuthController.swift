import Vapor
import Fluent
import JWT

struct AuthController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("auth")

        auth.post("register", use: register)
        auth.post("login", use: login)

        let authenticated = auth.grouped(AuthMiddleware())
        authenticated.get("me", use: me)
    }

     // MARK: - Me

    func me(req: Request) async throws -> AuthUserDTO {
        let user = try req.auth.require(User.self)

        return AuthUserDTO(
            id: try user.requireID(),
            email: user.email,
            createdAt: user.createdAt
        )
    }

    // MARK: - Register

    func register(req: Request) async throws -> Response {
        let input = try req.content.decode(RegisterDTO.self)

        let email = AuthValidator.normalizeEmail(input.email)

        try AuthValidator.validate(
            email: email,
            password: input.password
        )

        let existingUser = try await User.query(on: req.db)
            .filter(\.$email == email)
            .first()

        guard existingUser == nil else {
            throw Abort(.conflict, reason: "Cette adresse email est déjà utilisée.")
        }

        let passwordHash = try Bcrypt.hash(input.password)

        let user = User(
            email: email,
            passwordHash: passwordHash
        )

        try await user.save(on: req.db)

        let responseDTO = try await makeAuthResponse(for: user, req: req)

        let response = Response(status: .created)
        try response.content.encode(responseDTO)

        return response
    }

    // MARK: - Login

    func login(req: Request) async throws -> AuthResponseDTO {
        let input = try req.content.decode(LoginDTO.self)

        let email = AuthValidator.normalizeEmail(input.email)

        let user = try await User.query(on: req.db)
            .filter(\.$email == email)
            .first()

        guard let user,
              try Bcrypt.verify(input.password, created: user.passwordHash) else {
            throw Abort(
                .unauthorized,
                reason: "Email ou mot de passe incorrect."
            )
        }

        return try await makeAuthResponse(for: user, req: req)
    }

    // MARK: - Token

    private func makeAuthResponse(
        for user: User,
        req: Request
    ) async throws -> AuthResponseDTO {

        let userID = try user.requireID()
        let expiresAt = Date().addingTimeInterval(24 * 60 * 60)

        let payload = UserTokenPayload(
            subject: SubjectClaim(value: userID.uuidString),
            expiration: ExpirationClaim(value: expiresAt)
        )

        let token = try await req.jwt.sign(payload)

        let userDTO = AuthUserDTO(
            id: userID,
            email: user.email,
            createdAt: user.createdAt
        )

        return AuthResponseDTO(
            token: token,
            expiresAt: expiresAt,
            user: userDTO
        )
    }
}
