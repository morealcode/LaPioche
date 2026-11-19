@testable import App
import XCTVapor

final class LoanTests: XCTestCase {
    private func borrow(
        _ app: Application,
        gameID: UUID,
        memberID: UUID,
        afterResponse: (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.test(.POST, "loans", beforeRequest: { req in
            try req.content.encode(CreateLoanDTO(gameID: gameID, memberID: memberID))
        }, afterResponse: afterResponse)
    }

    func testBorrowGameReturnsCreated() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            try await borrow(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id)
            ) { res in
                XCTAssertEqual(res.status, .created)
                let loan = try res.content.decode(LoanDTO.self)
                XCTAssertEqual(loan.gameID, game.id)
                XCTAssertEqual(loan.memberID, member.id)
                XCTAssertNil(loan.returnedAt)
            }
        }
    }

    func testDueDateIsFourteenDaysAfterBorrowDate() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            try await borrow(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id)
            ) { res in
                let loan = try res.content.decode(LoanDTO.self)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let days = calendar.dateComponents([.day], from: loan.borrowedAt, to: loan.dueAt).day
                XCTAssertEqual(days, 14)
            }
        }
    }

    func testBorrowedGameIsNoLongerAvailable() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)

            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(member.id)) { _ in }

            try await app.test(.GET, "games/\(gameID)", afterResponse: { res async throws in
                XCTAssertFalse(try res.content.decode(GameDTO.self).isAvailable)
            })
        }
    }

    func testBorrowingAGameAlreadyOnLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let first = try await createMember(app, email: "first@example.com")
            let second = try await createMember(app, name: "Alex", email: "second@example.com")
            let gameID = try XCTUnwrap(game.id)

            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(first.id)) { _ in }
            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(second.id)) { res in
                XCTAssertEqual(res.status, .conflict)
            }
        }
    }

    func testBorrowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            let member = try await createMember(app)

            try await borrow(app, gameID: UUID(), memberID: try XCTUnwrap(member.id)) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testBorrowWithUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            let game = try await createGame(app)

            try await borrow(app, gameID: try XCTUnwrap(game.id), memberID: UUID()) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testReturnLoanReturnsUpdatedLoan() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)

            var loanID: UUID?

            try await borrow(app, gameID: gameID, memberID: memberID) { res in
                loanID = try res.content.decode(LoanDTO.self).id
            }

            try await app.test(.POST, "loans/\(try XCTUnwrap(loanID))/return") { res async throws in
                XCTAssertEqual(res.status, .ok)

                let loan = try res.content.decode(LoanDTO.self)
                XCTAssertNotNil(loan.returnedAt)
                XCTAssertEqual(loan.id, loanID)
            }
        }
    }

    func testReturnUnknownLoanReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.POST, "loans/\(UUID())/return") { res async throws in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testReturningAnAlreadyReturnedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let now = Date()

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now,
                dueAt: try Loan.dueDate(from: now),
                returnedAt: now
            )

            let loan = try await Loan.query(on: app.db).first()
            let loanID = try XCTUnwrap(loan?.id)

            try await app.test(.POST, "loans/\(loanID)/return") { res async throws in
                XCTAssertEqual(res.status, .conflict)
            }
        }
    }

    func testReturnedGameBecomesAvailableAgain() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let gameID = try XCTUnwrap(game.id)

            var loanID: UUID?

            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(member.id)) { res in
                loanID = try res.content.decode(LoanDTO.self).id
            }

            try await app.test(.POST, "loans/\(try XCTUnwrap(loanID))/return") { res async throws in
                XCTAssertEqual(res.status, .ok)
            }

            try await app.test(.GET, "games/\(gameID)") { res async throws in
                let updatedGame = try res.content.decode(GameDTO.self)
                XCTAssertTrue(updatedGame.isAvailable)
            }
        }
    }

    func testGetOverdueLoansReturnsOnlyOverdueLoans() async throws {
        try await withApp { app in
            let now = Date()

            // Emprunt actif en retard
            let overdueGame = try await createGame(app, title: "Overdue Game")
            let overdueMember = try await createMember(app)

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(overdueGame.id),
                memberID: try XCTUnwrap(overdueMember.id),
                borrowedAt: now.addingTimeInterval(-30 * 24 * 60 * 60),
                dueAt: now.addingTimeInterval(-16 * 24 * 60 * 60)
            )

            // Emprunt rendu, même si en retard
            let returnedGame = try await createGame(app, title: "Returned Game")
            let returnedMember = try await createMember(
                app,
                name: "Alex",
                email: "alex@example.com"
            )

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(returnedGame.id),
                memberID: try XCTUnwrap(returnedMember.id),
                borrowedAt: now.addingTimeInterval(-30 * 24 * 60 * 60),
                dueAt: now.addingTimeInterval(-16 * 24 * 60 * 60),
                returnedAt: now
            )

            // Emprunt actif mais pas encore en retard
            let futureGame = try await createGame(app, title: "Future Game")
            let futureMember = try await createMember(
                app,
                name: "Morgan",
                email: "morgan@example.com"
            )

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(futureGame.id),
                memberID: try XCTUnwrap(futureMember.id),
                borrowedAt: now,
                dueAt: now.addingTimeInterval(14 * 24 * 60 * 60)
            )

            try await app.test(
                .GET,
                "loans/overdue",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let loans = try res.content.decode([LoanDTO].self)

                    XCTAssertEqual(loans.count, 1)

                    XCTAssertEqual(loans.first?.gameID, overdueGame.id)
                    XCTAssertEqual(loans.first?.memberID, overdueMember.id)
                    XCTAssertNil(loans.first?.returnedAt)
                }
            )
        }
    }

    func testGetOverdueLoansReturnsEmptyList() async throws {
        try await withApp { app in
            try await app.test(
                .GET,
                "loans/overdue",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let loans = try res.content.decode([LoanDTO].self)

                    XCTAssertTrue(loans.isEmpty)
                }
            )
        }
    }

    func testGetOverdueLoansExcludesReturnedLoans() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let now = Date()

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now.addingTimeInterval(-30 * 24 * 60 * 60),
                dueAt: now.addingTimeInterval(-16 * 24 * 60 * 60),
                returnedAt: now
            )

            try await app.test(
                .GET,
                "loans/overdue",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let loans = try res.content.decode([LoanDTO].self)

                    XCTAssertTrue(loans.isEmpty)
                }
            )
        }
    }
}