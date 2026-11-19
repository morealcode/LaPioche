@testable import App
import XCTVapor

final class MemberTests: XCTestCase {
    func testCreateMemberReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                XCTAssertEqual(try res.content.decode(MemberDTO.self).name, "Camille")
            })
        }
    }

    func testCreateMemberWithInvalidEmailIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "not-an-email"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateMemberWithDuplicateEmailReturnsConflict() async throws {
        try await withApp { app in
            _ = try await createMember(app)

            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Autre", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testShowUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "members/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testUpdateMemberReturnsUpdatedMember() async throws {
        try await withApp { app in
            let member = try await createMember(app)

            try await app.test(.PUT, "members/\(try XCTUnwrap(member.id))", beforeRequest: { req in
                try req.content.encode(
                    CreateMemberDTO(name: "Camille Martin", email: "camille.martin@example.com")
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let updated = try res.content.decode(MemberDTO.self)
                XCTAssertEqual(updated.id, member.id)
                XCTAssertEqual(updated.name, "Camille Martin")
                XCTAssertEqual(updated.email, "camille.martin@example.com")
            })
        }
    }

    func testUpdateMemberCanKeepItsOwnEmail() async throws {
        try await withApp { app in
            let member = try await createMember(app)

            try await app.test(.PUT, "members/\(try XCTUnwrap(member.id))", beforeRequest: { req in
                try req.content.encode(
                    CreateMemberDTO(name: "Camille Martin", email: "camille@example.com")
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)

                let updated = try res.content.decode(MemberDTO.self)
                XCTAssertEqual(updated.email, "camille@example.com")
                XCTAssertEqual(updated.name, "Camille Martin")
            })
        }
    }

    func testUpdateMemberWithAnotherMembersEmailReturnsConflict() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            _ = try await createMember(app, name: "Alex", email: "alex@example.com")

            try await app.test(.PUT, "members/\(try XCTUnwrap(member.id))", beforeRequest: { req in
                try req.content.encode(
                    CreateMemberDTO(name: "Camille", email: "alex@example.com")
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testUpdateMemberWithInvalidEmailReturnsBadRequest() async throws {
        try await withApp { app in
            let member = try await createMember(app)

            try await app.test(.PUT, "members/\(try XCTUnwrap(member.id))", beforeRequest: { req in
                try req.content.encode(
                    CreateMemberDTO(name: "Camille", email: "not-an-email")
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testUpdateUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.PUT, "members/\(UUID())", beforeRequest: { req in
                try req.content.encode(
                    CreateMemberDTO(name: "Camille", email: "camille@example.com")
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testUpdateMemberWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.PUT, "members/not-a-uuid", beforeRequest: { req in
                try req.content.encode(
                    CreateMemberDTO(name: "Camille", email: "camille@example.com")
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testDeleteMemberReturnsNoContent() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let memberID = try XCTUnwrap(member.id)

            try await app.test(.DELETE, "members/\(memberID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .noContent)
            })

            try await app.test(.GET, "members/\(memberID)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "members/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testDeleteMemberWithActiveLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: Date(),
                dueAt: Date().addingTimeInterval(14 * 24 * 60 * 60)
            )

            try await app.test(.DELETE, "members/\(try XCTUnwrap(member.id))", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testDeleteMemberWithReturnedLoanReturnsConflict() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)
            let now = Date()

            try await insertLoan(
                app,
                gameID: try XCTUnwrap(game.id),
                memberID: try XCTUnwrap(member.id),
                borrowedAt: now.addingTimeInterval(-20 * 24 * 60 * 60),
                dueAt: now.addingTimeInterval(-6 * 24 * 60 * 60),
                returnedAt: now
            )

            try await app.test(.DELETE, "members/\(try XCTUnwrap(member.id))", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testDeleteMemberWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.DELETE, "members/not-a-uuid", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testGetMemberLoansReturnsAllLoans() async throws {
        try await withApp { app in
            let game = try await createGame(app)
            let member = try await createMember(app)

            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)

            let now = Date()

            // Emprunt actif
            try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: now,
                dueAt: now.addingTimeInterval(14 * 24 * 60 * 60)
            )

            // Emprunt rendu
            try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: now.addingTimeInterval(-20 * 24 * 60 * 60),
                dueAt: now.addingTimeInterval(-6 * 24 * 60 * 60),
                returnedAt: now
            )

            try await app.test(
                .GET,
                "members/\(memberID)/loans",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let loans = try res.content.decode([LoanDTO].self)

                    XCTAssertEqual(loans.count, 2)

                    // Vérifie qu'on récupère bien les deux types d'emprunts.
                    XCTAssertEqual(
                        loans.filter { $0.returnedAt == nil }.count,
                        1
                    )

                    XCTAssertEqual(
                        loans.filter { $0.returnedAt != nil }.count,
                        1
                    )

                    // Vérifie que les emprunts appartiennent au bon adhérent.
                    XCTAssertTrue(
                        loans.allSatisfy { $0.memberID == memberID }
                    )
                }
            )
        }
    }

    func testGetMemberLoansReturnsEmptyList() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let memberID = try XCTUnwrap(member.id)

            try await app.test(
                .GET,
                "members/\(memberID)/loans",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)

                    let loans = try res.content.decode([LoanDTO].self)

                    XCTAssertTrue(loans.isEmpty)
                }
            )
        }
    }

    func testGetLoansForUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(
                .GET,
                "members/\(UUID())/loans",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .notFound)
                }
            )
        }
    }

    func testGetMemberLoansWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(
                .GET,
                "members/not-a-uuid/loans",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }
}