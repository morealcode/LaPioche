import Fluent
import FluentSQLiteDriver
import Vapor
import JWT

func configure(_ app: Application) async throws {
    app.http.server.configuration.port = 8081

    let jwtSecret: String

    if let configuredSecret = Environment.get("JWT_SECRET") {
        jwtSecret = configuredSecret
    } else if app.environment == .testing {
        jwtSecret = "LA_PIOCHE_TEST_ONLY_SECRET_32_CHARS"
    } else if app.environment == .development {
        // Clé réservée au développement local. Ne pas utiliser en production.
        jwtSecret = "LA_PIOCHE_DEV_ONLY_SECRET_CHANGE_ME_32_CHARS"
    } else {
        throw Abort(.internalServerError, reason: "JWT_SECRET environment variable is required.")
    }

    guard jwtSecret.utf8.count >= 32 else {
        throw Abort(.internalServerError, reason: "JWT_SECRET must contain at least 32 bytes.")
    }

    await app.jwt.keys.add(
        hmac: HMACKey(from: jwtSecret),
        digestAlgorithm: .sha256
    )

    let cors = CORSMiddleware(configuration: .init(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS],
        allowedHeaders: [.accept, .contentType, .origin, .authorization]
    ))
    // CORS must wrap the error middleware so that error responses carry its headers too.
    app.middleware = .init()
    app.middleware.use(cors)
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))

    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    app.migrations.add(CreateGame())
    app.migrations.add(CreateMember())
    app.migrations.add(CreateLoan())
    app.migrations.add(CreateUser())
    try await app.autoMigrate()

    try routes(app)
}
