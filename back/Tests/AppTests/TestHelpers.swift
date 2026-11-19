@testable import App
import XCTVapor
import Vapor

// MARK: - Test authentication middleware

struct TestAuthMiddleware: AsyncMiddleware {
    let token: String

    func respond(
        to request: Request,
        chainingTo next: AsyncResponder
    ) async throws -> Response {

        // Les routes Auth restent accessibles sans authentification automatique.
        if !request.url.path.hasPrefix("/auth/") {
            request.headers.bearerAuthorization = BearerAuthorization(
                token: token
            )
        }

        return try await next.respond(to: request)
    }
}

// MARK: - Application helpers

func withApp(_ test: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)

    do {
        try await configure(app)

        let token = try await registerAndGetToken(app)

        // Authentification automatique des requêtes métier.
        app.middleware.use(TestAuthMiddleware(token: token))

        try await test(app)

    } catch {
        try? await app.asyncShutdown()
        throw error
    }

    try await app.asyncShutdown()
}

// Application sans authentification automatique.
// À utiliser pour tester les accès refusés.
func withUnauthenticatedApp(
    _ test: (Application) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)

    do {
        try await configure(app)
        try await test(app)

    } catch {
        try? await app.asyncShutdown()
        throw error
    }

    try await app.asyncShutdown()
}

// MARK: - Authentication helpers

func registerAndGetToken(
    _ app: Application,
    email: String = "staff@example.com",
    password: String = "password123"
) async throws -> String {

    var token: String?

    try await app.test(
        .POST,
        "auth/register",
        beforeRequest: { req in
            try req.content.encode(RegisterDTO(
                email: email,
                password: password
            ))
        },
        afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)

            let response = try res.content.decode(AuthResponseDTO.self)
            token = response.token
        }
    )

    return try XCTUnwrap(token)
}

// MARK: - Game helpers

func createGame(
    _ app: Application,
    title: String = "Catan",
    minPlayers: Int = 3,
    maxPlayers: Int = 4,
    durationMinutes: Int = 90
) async throws -> GameDTO {

    var game: GameDTO?

    try await app.test(
        .POST,
        "games",
        beforeRequest: { req in
            try req.content.encode(CreateGameDTO(
                title: title,
                minPlayers: minPlayers,
                maxPlayers: maxPlayers,
                durationMinutes: durationMinutes
            ))
        },
        afterResponse: { res async throws in
            game = try res.content.decode(GameDTO.self)
        }
    )

    return try XCTUnwrap(game)
}

// MARK: - Member helpers

func createMember(
    _ app: Application,
    name: String = "Camille",
    email: String = "camille@example.com"
) async throws -> MemberDTO {

    var member: MemberDTO?

    try await app.test(
        .POST,
        "members",
        beforeRequest: { req in
            try req.content.encode(CreateMemberDTO(
                name: name,
                email: email
            ))
        },
        afterResponse: { res async throws in
            member = try res.content.decode(MemberDTO.self)
        }
    )

    return try XCTUnwrap(member)
}

// MARK: - Loan helpers

func insertLoan(
    _ app: Application,
    gameID: UUID,
    memberID: UUID,
    borrowedAt: Date,
    dueAt: Date,
    returnedAt: Date? = nil
) async throws {

    let loan = Loan(
        gameID: gameID,
        memberID: memberID,
        borrowedAt: borrowedAt,
        dueAt: dueAt
    )

    loan.returnedAt = returnedAt

    try await loan.save(on: app.db)
}