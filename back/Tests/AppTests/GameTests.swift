@testable import App
import XCTVapor

final class GameTests: XCTestCase {
    func testCreateGameReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                let game = try res.content.decode(GameDTO.self)
                XCTAssertEqual(game.title, "Catan")
                XCTAssertTrue(game.isAvailable)
            })
        }
    }

    func testCreateGameWithEmptyTitleIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateGameWithInvertedPlayerBoundsIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 5, maxPlayers: 2, durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testListGames() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")

            try await app.test(.GET, "games", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode([GameDTO].self).count, 2)
            })
        }
    }

    func testShowGame() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode(GameDTO.self).id, id)
            })
        }
    }

    func testShowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testShowGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testPreflightRequestFromAnotherOriginIsAllowed() async throws {
        try await withApp { app in
            try await app.test(.OPTIONS, "games", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
                req.headers.replaceOrAdd(name: .accessControlRequestMethod, value: "POST")
                req.headers.replaceOrAdd(name: .accessControlRequestHeaders, value: "content-type")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
                XCTAssertTrue(res.headers[.accessControlAllowMethods].joined(separator: ",").contains("POST"))
            })
        }
    }

    func testErrorResponsesCarryTheCorsHeaders() async throws {
        try await withApp { app in
            try await app.test(.GET, "games/not-a-uuid", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
            })
        }
    }

    func testUpdateGameReturnsUpdatedGame() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.PUT, "games/\(id)", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Terraforming Mars",
                    minPlayers: 1,
                    maxPlayers: 5,
                    durationMinutes: 120
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let updatedGame = try res.content.decode(GameDTO.self)
                XCTAssertEqual(updatedGame.id, id)
                XCTAssertEqual(updatedGame.title, "Terraforming Mars")
                XCTAssertEqual(updatedGame.minPlayers, 1)
                XCTAssertEqual(updatedGame.maxPlayers, 5)
                XCTAssertEqual(updatedGame.durationMinutes, 120)
            })
        }
    }

    func testUpdateGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.PUT, "games/not-a-uuid", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan",
                    minPlayers: 3,
                    maxPlayers: 4,
                    durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testUpdateUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.PUT, "games/\(UUID())", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan",
                    minPlayers: 3,
                    maxPlayers: 4,
                    durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testUpdateGameWithInvalidBodyReturnsBadRequest() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.PUT, "games/\(id)", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "",
                    minPlayers: 3,
                    maxPlayers: 4,
                    durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testUpdateGameWithInvertedPlayerBoundsReturnsBadRequest() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.PUT, "games/\(id)", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan",
                    minPlayers: 5,
                    maxPlayers: 2,
                    durationMinutes: 90
                ))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testDeleteGameReturnsNoContent() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let id = try XCTUnwrap(game.id)

            try await app.test(.DELETE, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .noContent)
            })

            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "games/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteGameWithActiveLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let now = Date()
            let calendar = Calendar(identifier: .gregorian)

            let dueAt = calendar.date(
                byAdding: .day,
                value: 14,
                to: now
            )!

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now,
                dueAt: dueAt
            )

            try await app.test(
                .DELETE,
                "games/\(try XCTUnwrap(game.id))",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .conflict)
                }
            )
        }
    }

    func testDeleteGameWithReturnedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let now = Date()
            let calendar = Calendar(identifier: .gregorian)

            let borrowedAt = calendar.date(
                byAdding: .day,
                value: -20,
                to: now
            )!

            let dueAt = calendar.date(
                byAdding: .day,
                value: 14,
                to: borrowedAt
            )!

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: borrowedAt,
                dueAt: dueAt,
                returnedAt: now
            )

            try await app.test(
                .DELETE,
                "games/\(try XCTUnwrap(game.id))",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .conflict)
                }
            )
        }
    }

    func testSearchGamesByTitleIsCaseInsensitive() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")
            _ = try await createGame(app, title: "Dixit")
            _ = try await createGame(app, title: "Cat Lady")

            try await app.test(.GET, "games?q=cAt", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.count, 2)
                XCTAssertTrue(games.allSatisfy {
                    $0.title.localizedCaseInsensitiveContains("cAt")
                })
            })
        }
    }

    func testFilterGamesByPlayers() async throws {
        try await withApp { app in
            _ = try await createGame(
                app, title: "Catan",
                minPlayers: 3, maxPlayers: 4
            )
            _ = try await createGame(
                app, title: "Dixit",
                minPlayers: 3, maxPlayers: 6
            )
            _ = try await createGame(
                app, title: "Chess",
                minPlayers: 2, maxPlayers: 2
            )

            try await app.test(.GET, "games?players=4", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.count, 2)
                XCTAssertTrue(games.allSatisfy {
                    $0.minPlayers <= 4 && $0.maxPlayers >= 4
                })
            })
        }
    }

    func testFilterGamesByMaxDuration() async throws {
        try await withApp { app in
            _ = try await createGame(
                app, title: "Catan", durationMinutes: 90
            )
            _ = try await createGame(
                app, title: "Dixit", durationMinutes: 30
            )
            _ = try await createGame(
                app, title: "Terraforming Mars", durationMinutes: 120
            )

            try await app.test(.GET, "games?maxDuration=90", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let games = try res.content.decode([GameDTO].self)
                XCTAssertEqual(games.count, 2)
                XCTAssertTrue(games.allSatisfy {
                    $0.durationMinutes <= 90
                })
            })
        }
    }

    func testSearchGamesWithCombinedFilters() async throws {
        try await withApp { app in
            _ = try await createGame(
                app, title: "Catan",
                minPlayers: 3, maxPlayers: 4,
                durationMinutes: 90
            )
            _ = try await createGame(
                app, title: "Catan Junior",
                minPlayers: 2, maxPlayers: 4,
                durationMinutes: 30
            )
            _ = try await createGame(
                app, title: "Catan Extended",
                minPlayers: 3, maxPlayers: 6,
                durationMinutes: 120
            )

            try await app.test(
                .GET,
                "games?q=Catan&players=4&maxDuration=90",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let games = try res.content.decode([GameDTO].self)
                    XCTAssertEqual(games.count, 2)

                    XCTAssertTrue(games.allSatisfy {
                        $0.title.localizedCaseInsensitiveContains("Catan")
                            && $0.minPlayers <= 4
                            && $0.maxPlayers >= 4
                            && $0.durationMinutes <= 90
                    })
                }
            )
        }
    }

    func testSearchGamesWithInvalidPlayersReturnsBadRequest() async throws {
        let invalidValues = ["0", "-1", "abc", "1.5", ""]

        for value in invalidValues {
            try await withApp { app in
                try await app.test(
                    .GET,
                    "games?players=\(value)",
                    afterResponse: { res async throws in
                        XCTAssertEqual(
                            res.status,
                            .badRequest,
                            "Expected 400 for players=\(value)"
                        )
                    }
                )
            }
        }
    }

    func testSearchGamesWithInvalidMaxDurationReturnsBadRequest() async throws {
        let invalidValues = ["0", "-1", "abc", "1.5", ""]

        for value in invalidValues {
            try await withApp { app in
                try await app.test(
                    .GET,
                    "games?maxDuration=\(value)",
                    afterResponse: { res async throws in
                        XCTAssertEqual(
                            res.status,
                            .badRequest,
                            "Expected 400 for maxDuration=\(value)"
                        )
                    }
                )
            }
        }
    }

    func testListAvailableGames() async throws {
        try await withApp { app in
            let availableGame = try await createGame(
                app,
                title: "Catan"
            )

            let unavailableGame = try await createGame(
                app,
                title: "Dixit"
            )

            let member = try await createMember(app)

            let now = Date()
            let dueAt = Calendar.current.date(
                byAdding: .day,
                value: 14,
                to: now
            )!

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(unavailableGame.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now,
                dueAt: dueAt
            )

            try await app.test(
                .GET,
                "games?available=true",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let games = try res.content.decode([GameDTO].self)

                    XCTAssertEqual(games.count, 1)
                    XCTAssertEqual(games.first?.id, availableGame.id)
                    XCTAssertTrue(games.first?.isAvailable ?? false)
                }
            )
        }
    }

    func testListUnavailableGames() async throws {
        try await withApp { app in
            _ = try await createGame(app, title: "Catan")

            let unavailableGame = try await createGame(
                app,
                title: "Dixit"
            )

            let member = try await createMember(app)

            let now = Date()
            let dueAt = Calendar.current.date(
                byAdding: .day,
                value: 14,
                to: now
            )!

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(unavailableGame.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now,
                dueAt: dueAt
            )

            try await app.test(
                .GET,
                "games?available=false",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let games = try res.content.decode([GameDTO].self)

                    XCTAssertEqual(games.count, 1)
                    XCTAssertEqual(games.first?.id, unavailableGame.id)
                    XCTAssertFalse(games.first?.isAvailable ?? true)
                }
            )
        }
    }

    func testListGamesWithInvalidAvailableReturnsBadRequest() async throws {
        let invalidValues = ["yes", "no", "1", "0", "TRUE", "False", ""]

        for value in invalidValues {
            try await withApp { app in
                try await app.test(
                    .GET,
                    "games?available=\(value)",
                    afterResponse: { res async throws in
                        XCTAssertEqual(res.status, .badRequest)
                    }
                )
            }
        }
    }
}
