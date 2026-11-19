import Vapor

enum AuthValidator {
    static func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func validate(email: String, password: String) throws {
        let normalizedEmail = normalizeEmail(email)

        guard normalizedEmail.contains("@"),
              normalizedEmail.split(separator: "@").count == 2,
              normalizedEmail.split(separator: "@").last?.contains(".") == true else {
            throw Abort(.badRequest, reason: "Adresse email invalide.")
        }

        guard password.count >= 8 else {
            throw Abort(.badRequest, reason: "Le mot de passe doit contenir au moins 8 caractères.")
        }
    }
}
