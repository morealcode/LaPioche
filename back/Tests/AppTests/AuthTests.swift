@testable import App
import XCTVapor
import Vapor
import JWTKit
import Foundation

final class AuthTests: XCTestCase {

    // MARK: - Register

    func testRegisterReturnsCreatedWithToken() async throws {
        try await withApp { app in
            try await app.test(.POST, "auth/register", beforeRequest: { req in
                try req.content.encode(RegisterDTO(
                    email: "newstaff@example.com",
                    password: "password123"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)

                let response = try res.content.decode(AuthResponseDTO.self)

                XCTAssertFalse(response.token.isEmpty)
                XCTAssertGreaterThan(response.expiresAt, Date())
                XCTAssertEqual(response.user.email, "newstaff@example.com")
                XCTAssertNotNil(response.user.id)
            })
        }
    }

    func testRegisterWithInvalidEmailReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.POST, "auth/register", beforeRequest: { req in
                try req.content.encode(RegisterDTO(
                    email: "invalid-email",
                    password: "password123"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testRegisterWithShortPasswordReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.POST, "auth/register", beforeRequest: { req in
                try req.content.encode(RegisterDTO(
                    email: "newstaff@example.com",
                    password: "short"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testRegisterWithDuplicateEmailReturnsConflict() async throws {
        try await withApp { app in
            try await app.test(.POST, "auth/register", beforeRequest: { req in
                try req.content.encode(RegisterDTO(
                    email: "staff@example.com",
                    password: "password123"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testRegisterWithDifferentEmailCaseReturnsConflict() async throws {
        try await withApp { app in
            try await app.test(.POST, "auth/register", beforeRequest: { req in
                try req.content.encode(RegisterDTO(
                    email: "STAFF@EXAMPLE.COM",
                    password: "password123"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    // MARK: - Login

    func testLoginReturnsOKWithToken() async throws {
        try await withApp { app in
            try await app.test(.POST, "auth/login", beforeRequest: { req in
                try req.content.encode(LoginDTO(
                    email: "staff@example.com",
                    password: "password123"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let response = try res.content.decode(AuthResponseDTO.self)

                XCTAssertFalse(response.token.isEmpty)
                XCTAssertEqual(response.user.email, "staff@example.com")
                XCTAssertGreaterThan(response.expiresAt, Date())
            })
        }
    }

    func testLoginWithWrongPasswordReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(.POST, "auth/login", beforeRequest: { req in
                try req.content.encode(LoginDTO(
                    email: "staff@example.com",
                    password: "wrongpassword"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testLoginWithUnknownEmailReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(.POST, "auth/login", beforeRequest: { req in
                try req.content.encode(LoginDTO(
                    email: "unknown@example.com",
                    password: "password123"
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    // MARK: - Me

    func testMeReturnsAuthenticatedUser() async throws {
        try await withApp { app in
            let token = try await registerAndGetToken(
                app,
                email: "me@example.com"
            )

            try await app.test(.GET, "auth/me", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(
                    token: token
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let user = try res.content.decode(AuthUserDTO.self)

                XCTAssertEqual(user.email, "me@example.com")
            })
        }
    }

    func testMeWithoutTokenReturnsUnauthorized() async throws {
        try await withUnauthenticatedApp { app in
            try await app.test(.GET, "auth/me") { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            }
        }
    }

    func testMeWithInvalidTokenReturnsUnauthorized() async throws {
        try await withUnauthenticatedApp { app in
            try await app.test(.GET, "auth/me", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(
                    token: "invalid.token.value"
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    // MARK: - Deleted user

    func testMeWithDeletedUserReturnsUnauthorized() async throws {
        try await withApp { app in
            let token = try await registerAndGetToken(
                app,
                email: "deleted@example.com"
            )

            // Récupération sans filtre Fluent.
            let users = try await User.query(on: app.db).all()

            let user = try XCTUnwrap(
                users.first(where: { $0.email == "deleted@example.com" })
            )

            try await user.delete(on: app.db)

            try await app.test(.GET, "auth/me", beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(
                    token: token
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    // MARK: - Password security

    func testRegisterDoesNotExposePasswordOrHash() async throws {
        try await withApp { app in
            try await app.test(.POST, "auth/register", beforeRequest: { req in
                try req.content.encode(RegisterDTO(
                    email: "secure@example.com",
                    password: "password123"
                ))
            }, afterResponse: { res async throws in
                let body = String(buffer: res.body)

                XCTAssertFalse(body.contains("password123"))
                XCTAssertFalse(body.contains("passwordHash"))
                XCTAssertFalse(body.contains("password_hash"))
            })
        }
    }

    // MARK: - Protected routes

    func testProtectedRoutesWithoutTokenReturnUnauthorized() async throws {
        try await withUnauthenticatedApp { app in

            let protectedRequests: [(HTTPMethod, String)] = [
                (.GET, "games"),
                (.POST, "games"),
                (.GET, "games/\(UUID())"),
                (.PUT, "games/\(UUID())"),
                (.DELETE, "games/\(UUID())"),

                (.GET, "members/\(UUID())"),
                (.POST, "members"),
                (.PUT, "members/\(UUID())"),
                (.DELETE, "members/\(UUID())"),
                (.GET, "members/\(UUID())/loans"),

                (.POST, "loans"),
                (.GET, "loans/overdue"),
                (.POST, "loans/\(UUID())/return")
            ]

            for (method, path) in protectedRequests {
                try await app.test(method, path) { res async throws in
                    XCTAssertEqual(
                        res.status,
                        .unauthorized,
                        "\(method) \(path) devrait nécessiter une authentification"
                    )
                }
            }
        }
    }

    func testProtectedRoutesWithInvalidTokenReturnUnauthorized() async throws {
        try await withUnauthenticatedApp { app in

            let protectedRequests: [(HTTPMethod, String)] = [
                (.GET, "games"),
                (.GET, "members/\(UUID())"),
                (.GET, "loans/overdue")
            ]

            for (method, path) in protectedRequests {
                try await app.test(
                    method,
                    path,
                    beforeRequest: { req in
                        req.headers.bearerAuthorization = BearerAuthorization(
                            token: "invalid.token.value"
                        )
                    },
                    afterResponse: { res async throws in
                        XCTAssertEqual(
                            res.status,
                            .unauthorized,
                            "\(method) \(path) devrait refuser un JWT invalide"
                        )
                    }
                )
            }
        }
    }
}