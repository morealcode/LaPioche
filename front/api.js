import { API_URL } from "./config.js";

export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

// Le jeton est conservé uniquement dans l'onglet courant.
const TOKEN_KEY = "la-pioche-token";

export function getToken() {
  return sessionStorage.getItem(TOKEN_KEY);
}

export function setToken(token) {
  sessionStorage.setItem(TOKEN_KEY, token);
}

export function clearToken() {
  sessionStorage.removeItem(TOKEN_KEY);
}

// L'application enregistre ici son comportement lorsqu'un jeton est refusé.
let unauthorizedHandler = null;

export function onUnauthorized(handler) {
  unauthorizedHandler = handler;
}

const fieldLabels = {
  title: "Le titre",
  minPlayers: "Le nombre minimum de joueur·ses",
  maxPlayers: "Le nombre maximum de joueur·ses",
  durationMinutes: "La durée",
  name: "Le nom",
  email: "L'adresse e-mail",
  password: "Le mot de passe",
  players: "Le nombre de joueur·ses",
  maxDuration: "La durée maximale",
  available: "Le filtre de disponibilité",
};

const knownMessages = {
  "minPlayers must not exceed maxPlayers":
    "Le nombre minimum de joueur·ses ne peut pas dépasser le maximum.",
  "Game not found":
    "Ce jeu n'existe pas ou a déjà été supprimé.",
  "Member not found":
    "Cet·te adhérent·e n'existe pas ou a déjà été supprimé·e.",
  "Loan not found":
    "Cet emprunt n'existe pas.",
  "Loan has already been returned":
    "Cet emprunt a déjà été rendu.",
  "Invalid game id":
    "L'identifiant du jeu n'est pas valide.",
  "Invalid member id":
    "L'identifiant de l'adhérent·e n'est pas valide.",
  "Invalid loan id":
    "L'identifiant de l'emprunt n'est pas valide.",
  "Game is already on loan":
    "Ce jeu est déjà emprunté : il faut d'abord le rendre.",
  "Loan is already returned":
    "Cet emprunt a déjà été rendu.",
  "A game with loans cannot be deleted":
    "Suppression impossible : ce jeu a un historique d'emprunts, conservé même quand le jeu est rendu.",
  "A member with loans cannot be deleted":
    "Suppression impossible : cet·te adhérent·e a un historique d'emprunts, conservé même quand tout est rendu.",
  "A member with this email already exists":
    "Un·e autre adhérent·e utilise déjà cette adresse e-mail.",
  "Cannot delete a game with loan history":
    "Suppression impossible : ce jeu possède un historique d'emprunts.",

  "Email or password is incorrect":
    "Email ou mot de passe incorrect.",
  "Invalid email or password":
    "Email ou mot de passe incorrect.",
  "Cette adresse email est déjà utilisée.":
    "Cette adresse e-mail est déjà utilisée.",
  "Password must be at least 8 characters":
    "Le mot de passe doit contenir au moins 8 caractères.",
};

function translateValidation(part) {
  const label = (field) =>
    fieldLabels[field] ?? `Le champ « ${field} »`;

  let match;

  if ((match = part.match(/^(\w+) is (?:empty|required)$/))) {
    return `${label(match[1])} est obligatoire.`;
  }

  if ((match = part.match(/^(\w+) is less than minimum of (\d+)$/))) {
    return `${label(match[1])} doit être d'au moins ${match[2]}.`;
  }

  if ((match = part.match(/^(\w+) is not a(?:n)? Int$/))) {
    return `${label(match[1])} doit être un nombre entier.`;
  }

  if ((match = part.match(/^(\w+) is not a(?:n)? Bool$/))) {
    return `${label(match[1])} doit valoir « oui » ou « non ».`;
  }

  if (/^email is not a valid email address$/i.test(part)) {
    return "L'adresse e-mail n'est pas valide (exemple : nom@example.com).";
  }

  if (/^password is less than minimum of \d+$/i.test(part)) {
    return "Le mot de passe est trop court.";
  }

  return null;
}

const statusMessages = {
  400: "Les informations envoyées ne sont pas valides.",
  401: "Email ou mot de passe incorrect.",
  404: "Cet élément n'existe pas.",
  409: "Cette action est impossible dans l'état actuel des données.",
};

export function translateError(status, reason) {
  if (reason && knownMessages[reason]) {
    return knownMessages[reason];
  }

  const parts = (reason ?? "")
    .split(", ")
    .map((part) => translateValidation(part));

  if (parts.length > 0 && parts.every(Boolean)) {
    return parts.join(" ");
  }

  if (status >= 500) {
    return "Le serveur a rencontré une erreur. Réessayez dans un instant.";
  }

  return statusMessages[status] ??
    "Une erreur est survenue. Réessayez.";
}

/**
 * Effectue une requête HTTP.
 * authenticated=false est réservé aux routes publiques de connexion
 * et d'inscription.
 */
async function request(method, path, body, { authenticated = true } = {}) {
  const headers = {};

  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
  }

  const token = authenticated ? getToken() : null;

  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  let response;

  try {
    response = await fetch(`${API_URL}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(
      0,
      "Impossible de joindre le serveur. Vérifiez qu'il est bien lancé."
    );
  }

  if (response.status === 204) {
    return null;
  }

  const data = await response.json().catch(() => null);

  if (!response.ok) {
    if (response.status === 401 && authenticated && token) {
      clearToken();

      if (unauthorizedHandler) {
        unauthorizedHandler();
      }
    }

    throw new ApiError(
      response.status,
      translateError(response.status, data?.reason)
    );
  }

  return data;
}

export const api = {
  // --- Authentification --------------------------------------------------

  register: (credentials) =>
    request("POST", "/auth/register", credentials, {
      authenticated: false,
    }),

  login: (credentials) =>
    request("POST", "/auth/login", credentials, {
      authenticated: false,
    }),

  me: () => request("GET", "/auth/me"),

  // --- Jeux --------------------------------------------------------------

  listGames: (filters = {}) => {
    const params = new URLSearchParams();

    if (filters.q?.trim()) {
      params.set("q", filters.q.trim());
    }

    if (Number.isInteger(filters.players) && filters.players > 0) {
      params.set("players", String(filters.players));
    }

    if (
      Number.isInteger(filters.maxDuration) &&
      filters.maxDuration > 0
    ) {
      params.set("maxDuration", String(filters.maxDuration));
    }

    if (filters.available === true) {
      params.set("available", "true");
    }

    const query = params.toString();

    return request(
      "GET",
      `/games${query ? `?${query}` : ""}`
    );
  },

  createGame: (game) =>
    request("POST", "/games", game),

  updateGame: (id, game) =>
    request("PUT", `/games/${id}`, game),

  deleteGame: (id) =>
    request("DELETE", `/games/${id}`),

  // --- Adhérent·es -------------------------------------------------------

  listMembers: () =>
    request("GET", "/members"),

  createMember: (member) =>
    request("POST", "/members", member),

  updateMember: (id, member) =>
    request("PUT", `/members/${id}`, member),

  deleteMember: (id) =>
    request("DELETE", `/members/${id}`),

  // --- Emprunts ----------------------------------------------------------

  borrow: (gameID, memberID) =>
    request("POST", "/loans", { gameID, memberID }),

  listMemberLoans: (memberID) =>
    request("GET", `/members/${memberID}/loans`),

  returnLoan: (loanID) =>
    request("POST", `/loans/${loanID}/return`),

  listOverdueLoans: () =>
    request("GET", "/loans/overdue"),
};