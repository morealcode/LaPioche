import Vapor

func routes(_ app: Application) throws {
    // Routes publiques : inscription et connexion
    try app.register(collection: AuthController())

    // Toutes les routes métier nécessitent un JWT valide.
    let protected = app.grouped(AuthMiddleware())

    try protected.register(collection: GameController())
    try protected.register(collection: MemberController())
    try protected.register(collection: LoanController())
}

