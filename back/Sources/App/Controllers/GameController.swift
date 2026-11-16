import Fluent
import Vapor

struct GameController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let games = routes.grouped("games")
        games.get(use: index)
        games.post(use: create)
        games.get(":gameID", use: show)
        games.put(":gameID", use: update)
        games.delete(":gameID", use: delete)
    }

    @Sendable
    func index(req: Request) async throws -> [GameDTO] {
        let query = try req.query.decode(GameSearchQuery.self)

        var gamesQuery = Game.query(on: req.db)
            .with(\.$loans)

        if let q = query.q, !q.isEmpty {
            gamesQuery = gamesQuery.filter(\.$title ~~ "%\(q)%")
        }

        if let players = query.players {
            guard
                !players.isEmpty,
                players.allSatisfy({ $0.isASCII && $0.isNumber }),
                let playerCount = Int(players),
                playerCount > 0
            else {
                throw Abort(.badRequest, reason: "players must be a positive integer")
            }

            gamesQuery = gamesQuery
                .filter(\.$minPlayers <= playerCount)
                .filter(\.$maxPlayers >= playerCount)
        }

        if let maxDuration = query.maxDuration {
            guard
                !maxDuration.isEmpty,
                maxDuration.allSatisfy({ $0.isASCII && $0.isNumber }),
                let duration = Int(maxDuration),
                duration > 0
            else {
                throw Abort(.badRequest, reason: "maxDuration must be a positive integer")
            }

            gamesQuery = gamesQuery.filter(\.$durationMinutes <= duration)
        }

        if let available = query.available {
            guard available == "true" || available == "false" else {
                throw Abort(
                    .badRequest,
                    reason: "available must be true or false"
                )
            }
        }

        let games = try await gamesQuery.all()

        let filteredGames = games.filter { game in
            guard let available = query.available else {
                return true
            }

            let isAvailable = game.loans.allSatisfy {
                $0.returnedAt != nil
            }

            return isAvailable == (available == "true")
        }

        return filteredGames.map { $0.toDTO() }
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        try CreateGameDTO.validate(content: req)
        let dto = try req.content.decode(CreateGameDTO.self)
        try dto.ensureConsistentPlayerCount()

        let game = dto.toModel()
        try await game.save(on: req.db)
        
        let response = try await game.toDTO().encodeResponse(for: req)
        response.status = .created
        return response
    }

    @Sendable
    func show(req: Request) async throws -> GameDTO {
        try await findGame(req).toDTO()
    }

    private func findGame(_ req: Request) async throws -> Game {
        guard let gameID = req.parameters.get("gameID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid game id")
        }
        guard let game = try await Game.query(on: req.db)
            .filter(\.$id == gameID)
            .with(\.$loans)
            .first()
        else {
            throw Abort(.notFound, reason: "Game not found")
        }
        return game
    }

    @Sendable
    func update(req: Request) async throws -> GameDTO {
        try CreateGameDTO.validate(content: req)
        let dto = try req.content.decode(CreateGameDTO.self)
        try dto.ensureConsistentPlayerCount()

        let game = try await findGame(req)

        game.title = dto.title
        game.minPlayers = dto.minPlayers
        game.maxPlayers = dto.maxPlayers
        game.durationMinutes = dto.durationMinutes

        try await game.save(on: req.db)

        return game.toDTO()
    }

    @Sendable
    func delete(req: Request) async throws -> Response {
        let game = try await findGame(req)

        guard game.loans.isEmpty else {
            throw Abort(.conflict, reason: "Cannot delete a game with loan history")
        }

        try await game.delete(on: req.db)

        return Response(status: .noContent)
    }
}
