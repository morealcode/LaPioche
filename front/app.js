import { API_URL } from "./config.js";
import { api } from "./api.js";

const $ = (selector, root = document) => root.querySelector(selector);

$("#docs-link").href = API_URL;

const dateFormat = new Intl.DateTimeFormat("fr-FR", { dateStyle: "long" });
const formatDate = (iso) => dateFormat.format(new Date(iso));

// Construit un élément sans jamais passer par innerHTML : les données de
// l'API (titres, noms) sont insérées comme du texte.
function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  node.append(...children);
  return node;
}

function button(label, onClick, className = "") {
  return el("button", { type: "button", class: className, onclick: onClick }, label);
}

function toast(message, isError = false) {
  const node = el("p", { class: isError ? "toast error" : "toast" }, message);
  $("#toasts").append(node);
  setTimeout(() => node.remove(), 5000);
}

// Exécute une action déclenchée par un bouton et affiche l'erreur de l'API.
async function run(action) {
  try {
    await action();
  } catch (error) {
    toast(error.message, true);
  }
}

function showFormError(dialog, error) {
  const target = $(".form-error", dialog);
  target.textContent = error ? error.message : "";
  target.hidden = !error;
}

for (const cancel of document.querySelectorAll("[data-cancel]")) {
  cancel.addEventListener("click", () => cancel.closest("dialog").close());
}

// Branche un formulaire de boîte de dialogue sur un appel à l'API.
// L'erreur renvoyée par l'API reste affichée dans la boîte, qui ne se ferme
// qu'en cas de succès.
function bindSubmit(dialog, form, handler) {
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    showFormError(dialog, null);
    try {
      await handler(new FormData(form));
      dialog.close();
      await refresh();
    } catch (error) {
      showFormError(dialog, error);
    }
  });
}

// --- Onglets ---------------------------------------------------------------

const tabs = ["games", "members"];

function currentTab() {
  const name = location.hash.slice(1);
  return tabs.includes(name) ? name : "games";
}

async function refresh() {
  const tab = currentTab();
  for (const name of tabs) {
    $(`#${name}`).hidden = name !== tab;
    $(`[data-tab="${name}"]`).toggleAttribute("aria-current", name === tab);
  }
  await run(tab === "games" ? loadGames : loadMembers);
}

window.addEventListener("hashchange", refresh);

// --- Jeux ------------------------------------------------------------------

async function loadGames() {
  const games = await api.listGames();
  $("#games-empty").hidden = games.length > 0;
  $("#games-list").replaceChildren(...games.map(gameCard));
}

function gameCard(game) {
  const players =
    game.minPlayers === game.maxPlayers ? `${game.minPlayers}` : `${game.minPlayers} à ${game.maxPlayers}`;
  const status = game.isAvailable
    ? el("span", { class: "badge ok" }, "Disponible")
    : el("span", { class: "badge busy" }, "Emprunté");

  const actions = el("div", { class: "actions" });

  actions.append(
    button("Modifier", () => openEditGameDialog(game)),
    button("Supprimer", () => openDeleteGameDialog(game), "danger"),
  );

  if (game.isAvailable) {
    actions.append(button("Emprunter", () => openBorrowDialog(game), "primary"));
  } else {
    actions.append(button("Rendre", () => returnGame(game), "primary"));
  }

  return el(
    "li",
    { class: "card" },
    el("div", { class: "card-head" }, el("h3", {}, game.title), status),
    el("p", { class: "meta" }, `${players} joueur·ses · ${game.durationMinutes} min`),
    actions,
  );
}

const gameDialog = $("#game-dialog");
const gameForm = $("#game-form");
const gameDialogTitle = $("h2", gameForm);

let editingGame = null;

$("#add-game").addEventListener("click", () => {
  editingGame = null;
  gameForm.reset();
  gameDialogTitle.textContent = "Ajouter un jeu";
  showFormError(gameDialog, null);
  gameDialog.showModal();
});

function openEditGameDialog(game) {
  editingGame = game;

  gameForm.elements.title.value = game.title;
  gameForm.elements.minPlayers.value = game.minPlayers;
  gameForm.elements.maxPlayers.value = game.maxPlayers;
  gameForm.elements.durationMinutes.value = game.durationMinutes;

  gameDialogTitle.textContent = "Modifier un jeu";
  showFormError(gameDialog, null);
  gameDialog.showModal();
}

bindSubmit(gameDialog, gameForm, (data) => {
  const payload = {
    title: data.get("title").trim(),
    minPlayers: Number(data.get("minPlayers")),
    maxPlayers: Number(data.get("maxPlayers")),
    durationMinutes: Number(data.get("durationMinutes")),
  };

  return editingGame
    ? api.updateGame(editingGame.id, payload)
    : api.createGame(payload);
});

const deleteGameDialog = $("#delete-game-dialog");
const deleteGameForm = $("#delete-game-form");

let deletingGame = null;

function openDeleteGameDialog(game) {
  deletingGame = game;

  $("#delete-game-message").textContent =
    `Voulez-vous vraiment supprimer « ${game.title} » ?`;

  showFormError(deleteGameDialog, null);
  deleteGameDialog.showModal();
}

deleteGameForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  showFormError(deleteGameDialog, null);

  try {
    await api.deleteGame(deletingGame.id);
    deleteGameDialog.close();
    deletingGame = null;
    await refresh();
    toast("Le jeu a bien été supprimé.");
  } catch (error) {
    showFormError(deleteGameDialog, error);
  }
});

// --- Emprunts --------------------------------------------------------------

const borrowDialog = $("#borrow-dialog");
const borrowForm = $("#borrow-form");
let borrowedGame = null;

async function openBorrowDialog(game) {
  await run(async () => {
    const members = await api.listMembers();
    if (members.length === 0) {
      toast("Ajoutez d'abord un·e adhérent·e pour pouvoir emprunter.", true);
      return;
    }
    borrowedGame = game;
    $("#borrow-dialog-title").textContent = `Emprunter « ${game.title} »`;
    $("select", borrowForm).replaceChildren(
      ...members.map((member) => el("option", { value: member.id }, `${member.name} (${member.email})`)),
    );
    showFormError(borrowDialog, null);
    borrowDialog.showModal();
  });
}

bindSubmit(borrowDialog, borrowForm, async (data) => {
  const loan = await api.borrow(borrowedGame.id, data.get("memberID"));
  toast(`« ${borrowedGame.title} » emprunté, à rendre avant le ${formatDate(loan.dueAt)}.`);
});

async function returnGame(game) {
  await run(async () => {
    // Récupérer tous les adhérents.
    const members = await api.listMembers();

    // Récupérer les emprunts de chaque adhérent.
    const loansByMember = await Promise.all(
      members.map((member) => api.listMemberLoans(member.id))
    );

    // Retrouver l'emprunt actif correspondant au jeu.
    const loan = loansByMember
      .flat()
      .find(
        (loan) =>
          loan.gameID === game.id &&
          loan.returnedAt == null
      );

    if (!loan || !loan.id) {
      throw new Error("Aucun emprunt en cours n'a été trouvé pour ce jeu.");
    }

    // Effectuer le retour.
    await api.returnLoan(loan.id);

    // Actualiser les jeux sans recharger la page.
    await refresh();

    // Confirmer le retour.
    toast(`« ${game.title} » a bien été rendu.`);
  });
}

// Détermine l'état d'un emprunt.
function getLoanStatus(loan, now = new Date()) {
  if (loan.returnedAt != null) {
    return {
      label: "Rendu",
      className: "returned",
    };
  }

  if (new Date(loan.dueAt) < now) {
    return {
      label: "En retard",
      className: "overdue",
    };
  }

  return {
    label: "En cours",
    className: "active",
  };
}

// --- Consultation des emprunts d'un·e adhérent·e ----------------------------

const memberLoansDialog = $("#member-loans-dialog");
const memberLoansList = $("#member-loans-list");
const memberLoansEmpty = $("#member-loans-empty");
const memberLoansTitle = $("#member-loans-title");
const memberLoansError = $("#member-loans-error");

async function openMemberLoans(member) {
  memberLoansTitle.textContent = `Emprunts de ${member.name}`;

  memberLoansList.replaceChildren();
  memberLoansEmpty.hidden = true;
  memberLoansError.hidden = true;
  memberLoansError.textContent = "";

  memberLoansDialog.showModal();

  try {
    // Récupérer les emprunts de l'adhérent·e.
    const loans = await api.listMemberLoans(member.id);

    // Récupérer les jeux pour retrouver leurs titres.
    const games = await api.listGames();

    const gamesById = new Map(
      games.map((game) => [game.id, game])
    );

    // Afficher le message si aucun emprunt n'existe.
    if (loans.length === 0) {
      memberLoansEmpty.hidden = false;
      return;
    }

    // Construire la liste des emprunts.
    const rows = loans.map((loan) => {
      const game = gamesById.get(loan.gameID);

      const gameTitle = game
        ? game.title
        : "Jeu introuvable";

      const status = getLoanStatus(loan);

      return el(
        "li",
        { class: "loan-row" },

        el(
          "div",
          { class: "loan-main" },

          el(
            "p",
            { class: "loan-title" },
            gameTitle
          ),

          el(
            "p",
            { class: "loan-dates" },
            `Emprunté le : ${formatDate(loan.borrowedAt)}`
          ),

          el(
            "p",
            { class: "loan-dates" },
            `Retour prévu le : ${formatDate(loan.dueAt)}`
          )
        ),

        el(
          "span",
          { class: `loan-status ${status.className}` },
          status.label
        )
      );
    });

    memberLoansList.replaceChildren(...rows);

  } catch (error) {
    memberLoansError.textContent = error.message;
    memberLoansError.hidden = false;
  }
}

// --- Adhérent·es -----------------------------------------------------------

async function loadMembers() {
  const members = await api.listMembers();
  $("#members-empty").hidden = members.length > 0;
  $("#members-list").replaceChildren(...members.map(memberRow));
}

function memberRow(member) {
  const actions = el("div", { class: "actions" });

  actions.append(
    button(
      "Voir les emprunts",
      () => openMemberLoans(member)
    ),

    button(
      "Modifier",
      () => openEditMemberDialog(member)
    ),

    button(
      "Supprimer",
      () => openDeleteMemberDialog(member),
      "danger"
    )
  );

  return el(
    "li",
    { class: "row" },

    el(
      "div",
      { class: "row-main" },

      el(
        "p",
        {},
        el("strong", {}, member.name)
      ),

      el(
        "p",
        { class: "meta" },
        member.email
      )
    ),

    actions
  );
}

const memberDialog = $("#member-dialog");
const memberForm = $("#member-form");
const memberDialogTitle = $("h2", memberForm);

let editingMember = null;

$("#add-member").addEventListener("click", () => {
  editingMember = null;
  memberForm.reset();
  memberDialogTitle.textContent = "Ajouter un·e adhérent·e";
  showFormError(memberDialog, null);
  memberDialog.showModal();
});

function openEditMemberDialog(member) {
  editingMember = member;

  memberForm.elements.name.value = member.name;
  memberForm.elements.email.value = member.email;

  memberDialogTitle.textContent = "Modifier un·e adhérent·e";
  showFormError(memberDialog, null);
  memberDialog.showModal();
}

bindSubmit(memberDialog, memberForm, (data) => {
  const payload = {
    name: data.get("name").trim(),
    email: data.get("email").trim(),
  };

  return editingMember
    ? api.updateMember(editingMember.id, payload)
    : api.createMember(payload);
});

const deleteMemberDialog = $("#delete-member-dialog");
const deleteMemberForm = $("#delete-member-form");

let deletingMember = null;

function openDeleteMemberDialog(member) {
  deletingMember = member;

  $("#delete-member-message").textContent =
    `Voulez-vous vraiment supprimer l'adhérent·e « ${member.name} » ?`;

  showFormError(deleteMemberDialog, null);
  deleteMemberDialog.showModal();
}

deleteMemberForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  showFormError(deleteMemberDialog, null);

  try {
    await api.deleteMember(deletingMember.id);
    deleteMemberDialog.close();
    deletingMember = null;
    await refresh();
    toast("L'adhérent·e a bien été supprimé·e.");
  } catch (error) {
    showFormError(deleteMemberDialog, error);
  }
});

refresh();
