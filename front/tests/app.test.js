import { assertEqual, assertIncludes, assertTrue, test, waitFor } from "./runner.js";
import { mountApp } from "./helpers.js";

const catan = { id: "g1", title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90, isAvailable: true };
const dixit = { id: "g2", title: "Dixit", minPlayers: 3, maxPlayers: 6, durationMinutes: 30, isAvailable: false };
const camille = { id: "m1", name: "Camille", email: "camille@example.com" };

const cardOf = (app, title) => app.$$("#games-list .card").find((card) => card.querySelector("h3").textContent === title);

// --- Jeux

test("games list shows one card per game with its availability", async () => {
  const app = await mountApp({ "GET /games": [catan, dixit] });
  await waitFor(() => app.$$("#games-list .card").length === 2, "deux cartes de jeu");
  assertIncludes(cardOf(app, "Catan").textContent, "Disponible");
  assertIncludes(cardOf(app, "Dixit").textContent, "Emprunté");
  assertIncludes(cardOf(app, "Catan").textContent, "3 à 4 joueur·ses · 90 min");
});

/*test("only an available game offers Borrow", async () => {
  const app = await mountApp({ "GET /games": [catan, dixit] });
  await waitFor(() => app.$$("#games-list .card").length === 2);
  const labels = (title) => [...cardOf(app, title).querySelectorAll("button")].map((button) => button.textContent);
  assertTrue(labels("Catan").includes("Emprunter"), "Catan devrait proposer Emprunter");
  assertTrue(!labels("Dixit").includes("Emprunter"), "Dixit est emprunté, il ne doit pas proposer Emprunter");
});*/

test("available games offer Borrow and borrowed games offer Return", async () => {
  const app = await mountApp({ "GET /games": [catan, dixit] });

  await waitFor(() => app.$$("#games-list .card").length === 2);

  const labels = (title) =>
    [...cardOf(app, title).querySelectorAll("button")]
      .map((button) => button.textContent);

  assertTrue(
    labels("Catan").includes("Emprunter"),
    "Catan devrait proposer Emprunter"
  );

  assertTrue(
    labels("Dixit").includes("Rendre"),
    "Dixit devrait proposer Rendre"
  );

  assertTrue(
    !labels("Dixit").includes("Emprunter"),
    "Dixit ne devrait pas proposer Emprunter"
  );
});

test("with no game, a message invites to add one", async () => {
  const app = await mountApp({ "GET /games": [] });
  await waitFor(() => !app.$("#games-empty").hidden);
  assertIncludes(app.$("#games-empty").textContent, "ne contient aucun jeu");
  assertIncludes(app.$("#games-empty").textContent, "Ajouter un jeu");
});

test("adding a game posts the form then reloads the list", async () => {
  const app = await mountApp({ "GET /games": [catan], "POST /games": [201, { ...catan, id: "g3", title: "Dixit" }] });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Ajouter un jeu");
  const form = app.$("#game-form");
  form.elements.title.value = "  Dixit ";
  form.elements.minPlayers.value = "3";
  form.elements.maxPlayers.value = "6";
  form.elements.durationMinutes.value = "30";
  form.requestSubmit();
  await waitFor(() => app.calls.some((call) => call.method === "POST" && call.path === "/games"), "l'appel POST /games");
  assertEqual(app.calls.find((call) => call.method === "POST").body, {
    title: "Dixit",
    minPlayers: 3,
    maxPlayers: 6,
    durationMinutes: 30,
  });
  await waitFor(() => !app.$("#game-dialog").open, "la boîte se ferme");
});

test("a validation error is shown in French and the dialog stays open", async () => {
  const app = await mountApp({
    "GET /games": [],
    "POST /games": [400, { error: true, reason: "title is empty, durationMinutes is less than minimum of 1" }],
  });
  await waitFor(() => !app.$("#games-empty").hidden, "la page est chargée");
  app.click("Ajouter un jeu");
  app.$("#game-form").requestSubmit();
  await waitFor(() => !app.$("#game-dialog .form-error").hidden, "le message d'erreur");
  assertEqual(app.$("#game-dialog .form-error").textContent, "Le titre est obligatoire. La durée doit être d'au moins 1.");
  assertTrue(app.$("#game-dialog").open, "la boîte devrait rester ouverte");
});

test("editing a game sends a PUT request", async () => {
  const updatedGame = { ...catan, title: "Catan édition spéciale" };

  const app = await mountApp({
    "GET /games": [catan],
    "PUT /games/g1": updatedGame,
  });

  await waitFor(() => app.$$("#games-list .card").length === 1);

  app.click("Modifier", cardOf(app, "Catan"));

  const form = app.$("#game-form");
  assertEqual(form.elements.title.value, "Catan");

  form.elements.title.value = "Catan édition spéciale";
  form.requestSubmit();

  await waitFor(
    () => app.calls.some((call) => call.method === "PUT" && call.path === "/games/g1"),
    "l'appel PUT /games/g1",
  );

  assertEqual(
    app.calls.find((call) => call.method === "PUT").body,
    {
      title: "Catan édition spéciale",
      minPlayers: 3,
      maxPlayers: 4,
      durationMinutes: 90,
    },
  );

  await waitFor(() => !app.$("#game-dialog").open, "la boîte de modification se ferme");
});

test("a deletion refusal is displayed in French", async () => {
  const app = await mountApp({
    "GET /games": [catan],
    "DELETE /games/g1": [
      409,
      { error: true, reason: "A game with loans cannot be deleted" },
    ],
  });

  await waitFor(() => app.$$("#games-list .card").length === 1);

  app.click("Supprimer", cardOf(app, "Catan"));

  await waitFor(() => app.$("#delete-game-dialog").open, "la confirmation de suppression");

  app.$("#delete-game-form").requestSubmit();

  await waitFor(
    () => !app.$("#delete-game-dialog .form-error").hidden,
    "le message de refus",
  );

  assertEqual(
    app.$("#delete-game-dialog .form-error").textContent,
    "Suppression impossible : ce jeu a un historique d'emprunts, conservé même quand le jeu est rendu.",
  );

  assertTrue(
    app.$("#delete-game-dialog").open,
    "la boîte de confirmation devrait rester ouverte",
  );
});

// --- Emprunts

test("borrowing a game sends the game and the chosen member", async () => {
  const app = await mountApp({
    "GET /games": [catan],
    "GET /members": [camille],
    "POST /loans": [201, { id: "l1", gameID: "g1", memberID: "m1", borrowedAt: new Date().toISOString(), dueAt: new Date().toISOString() }],
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Emprunter", cardOf(app, "Catan"));
  await waitFor(() => app.$("#borrow-dialog").open, "la boîte d'emprunt");
  app.$("#borrow-form").requestSubmit();
  await waitFor(() => app.calls.some((call) => call.method === "POST" && call.path === "/loans"), "l'appel POST /loans");
  assertEqual(app.calls.find((call) => call.path === "/loans").body, { gameID: "g1", memberID: "m1" });
  await waitFor(() => app.$("#toasts").textContent.includes("emprunté"), "le message de confirmation");
});

test("borrowing without any member explains that one must be added first", async () => {
  const app = await mountApp({ "GET /games": [catan], "GET /members": [] });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Emprunter", cardOf(app, "Catan"));
  await waitFor(() => app.$("#toasts").textContent.includes("Ajoutez d'abord"), "le message d'aide");
  assertTrue(!app.$("#borrow-dialog").open, "la boîte d'emprunt ne doit pas s'ouvrir");
});

test("returning a game calls the correct route and updates availability", async () => {
  let returned = false;

  const activeLoan = {
    id: "l1",
    gameID: "g2",
    memberID: "m1",
    borrowedAt: new Date().toISOString(),
    dueAt: new Date().toISOString(),
    returnedAt: null,
  };

  const app = await mountApp({
    "GET /games": () => [
      returned ? { ...dixit, isAvailable: true } : dixit,
    ],

    "GET /members": [camille],

    "GET /members/m1/loans": [activeLoan],

    "POST /loans/l1/return": () => {
      returned = true;
      return [200, { ...activeLoan, returnedAt: new Date().toISOString() }];
    },
  });

  await waitFor(() => app.$$("#games-list .card").length === 1);

  const card = cardOf(app, "Dixit");

  assertIncludes(card.textContent, "Emprunté");

  app.click("Rendre", card);

  // Vérifier que la bonne route est appelée.
  await waitFor(
    () => app.calls.some(
      (call) =>
        call.method === "POST" &&
        call.path === "/loans/l1/return"
    ),
    "l'appel POST /loans/l1/return"
  );

  // Vérifier que l'affichage est actualisé.
  await waitFor(
    () => cardOf(app, "Dixit")?.textContent.includes("Disponible"),
    "le jeu devrait devenir disponible"
  );

  assertTrue(
    [...cardOf(app, "Dixit").querySelectorAll("button")]
      .some((button) => button.textContent === "Emprunter"),
    "le bouton Emprunter devrait réapparaître"
  );

  assertIncludes(
    app.$("#toasts").textContent,
    "Dixit » a bien été rendu"
  );
});

test("a failed return is displayed in French", async () => {
  const activeLoan = {
    id: "l1",
    gameID: "g2",
    memberID: "m1",
    borrowedAt: new Date().toISOString(),
    dueAt: new Date().toISOString(),
    returnedAt: null,
  };

  const app = await mountApp({
    "GET /games": [dixit],

    "GET /members": [camille],

    "GET /members/m1/loans": [activeLoan],

    "POST /loans/l1/return": [
      409,
      {
        error: true,
        reason: "Loan has already been returned",
      },
    ],
  });

  await waitFor(() => app.$$("#games-list .card").length === 1);

  app.click("Rendre", cardOf(app, "Dixit"));

  await waitFor(
    () => app.calls.some(
      (call) =>
        call.method === "POST" &&
        call.path === "/loans/l1/return"
    ),
    "l'appel de retour"
  );

  await waitFor(
    () => app.$("#toasts").textContent.includes("Cet emprunt a déjà été rendu."),
    "le message d'erreur en français"
  );

  assertIncludes(
    cardOf(app, "Dixit").textContent,
    "Emprunté"
  );
});

test("overdue tab displays the late loan with game, member, due date and delay", async () => {
  const dueAt = new Date(
    Date.now() - 5 * 24 * 60 * 60 * 1000
  ).toISOString();

  const overdueLoan = {
    id: "l1",
    gameID: "g1",
    memberID: "m1",
    borrowedAt: new Date(Date.now() - 20 * 24 * 60 * 60 * 1000).toISOString(),
    dueAt,
    returnedAt: null,
  };

  const app = await mountApp({
    "GET /loans/overdue": [overdueLoan],
    "GET /games": [catan],
    "GET /members": [camille],
  }, { hash: "#overdue" });

  await waitFor(
    () => app.$$("#overdue-list .loan-row").length === 1,
    "l'emprunt en retard devrait être affiché"
  );

  const content = app.$("#overdue-list").textContent;

  // Le titre du jeu doit apparaître.
  assertIncludes(content, "Catan");

  // Le nom de l'adhérente doit apparaître.
  assertIncludes(content, "Camille");

  // La date de retour prévue doit apparaître.
  const expectedDate = new Intl.DateTimeFormat("fr-FR", {
    dateStyle: "long",
  }).format(new Date(dueAt));

  assertIncludes(content, expectedDate);

  // Le retard doit être indiqué par un texte contenant un nombre de jours.
  assertTrue(
    /En retard de \d+ jours?/.test(content),
    "le nombre de jours de retard devrait être affiché"
  );

  // Le compteur doit indiquer un emprunt en retard.
  assertEqual(app.$("#overdue-count").textContent, "1");

  // Le signalement ne doit pas reposer uniquement sur la couleur.
  assertIncludes(content, "En retard");

  // La bonne route doit avoir été appelée.
  assertTrue(
    app.calls.some(
      (call) =>
        call.method === "GET" &&
        call.path === "/loans/overdue"
    ),
    "la route des emprunts en retard devrait être appelée"
  );
});

test("overdue tab displays an empty message when there are no late loans", async () => {
  const app = await mountApp({
    "GET /loans/overdue": [],
    "GET /games": [catan],
    "GET /members": [camille],
  }, { hash: "#overdue" });

  await waitFor(
    () => !app.$("#overdue-empty").hidden,
    "le message indiquant l'absence de retard"
  );

  // Un message explicite doit être affiché.
  assertIncludes(
    app.$("#overdue-empty").textContent,
    "Aucun emprunt en retard"
  );

  // Aucun emprunt ne doit apparaître.
  assertEqual(
    app.$$("#overdue-list .loan-row").length,
    0,
    "la liste des retards devrait être vide"
  );

  // Le compteur doit être à zéro.
  assertEqual(
    app.$("#overdue-count").textContent,
    "0"
  );
});

// --- Adhérent·es

test("members tab lists the members", async () => {
  const app = await mountApp({ "GET /members": [camille] }, { hash: "#members" });
  await waitFor(() => app.$$("#members-list .row").length === 1);
  assertIncludes(app.$("#members-list .row").textContent, "Camille");
  assertIncludes(app.$("#members-list .row").textContent, "camille@example.com");
});

test("with no member, a message invites to add one", async () => {
  const app = await mountApp({ "GET /members": [] }, { hash: "#members" });
  await waitFor(() => !app.$("#members-empty").hidden);
  assertIncludes(app.$("#members-empty").textContent, "Ajouter un·e adhérent·e");
});

test("adding a member posts the form", async () => {
  const app = await mountApp({ "GET /members": [], "POST /members": [201, camille] }, { hash: "#members" });
  await waitFor(() => !app.$("#members-empty").hidden);
  app.click("Ajouter un·e adhérent·e");
  const form = app.$("#member-form");
  form.elements.name.value = " Camille ";
  form.elements.email.value = "camille@example.com";
  form.requestSubmit();
  await waitFor(() => app.calls.some((call) => call.method === "POST" && call.path === "/members"), "l'appel POST /members");
  assertEqual(app.calls.find((call) => call.method === "POST").body, { name: "Camille", email: "camille@example.com" });
});

test("an email already in use is shown in French", async () => {
  const app = await mountApp(
    { "GET /members": [], "POST /members": [409, { error: true, reason: "A member with this email already exists" }] },
    { hash: "#members" },
  );
  await waitFor(() => !app.$("#members-empty").hidden);
  app.click("Ajouter un·e adhérent·e");
  app.$("#member-form").requestSubmit();
  await waitFor(() => !app.$("#member-dialog .form-error").hidden, "le message d'erreur");
  assertIncludes(app.$("#member-dialog .form-error").textContent, "utilise déjà cette adresse e-mail");
});

test("editing a member sends a PUT request with the prefilled form", async () => {
  const app = await mountApp({
    "GET /members": [camille],
    "PUT /members/m1": {
      ...camille,
      name: "Camille Martin",
    },
  }, { hash: "#members" });

  await waitFor(() => app.$$("#members-list .row").length === 1);

  app.click("Modifier", app.$("#members-list .row")[0]);

  const form = app.$("#member-form");

  assertEqual(form.elements.name.value, "Camille");
  assertEqual(form.elements.email.value, "camille@example.com");

  form.elements.name.value = "Camille Martin";
  form.requestSubmit();

  await waitFor(
    () => app.calls.some((call) => call.method === "PUT" && call.path === "/members/m1"),
    "l'appel PUT /members/m1",
  );

  assertEqual(app.calls.find((call) => call.method === "PUT").body, {
    name: "Camille Martin",
    email: "camille@example.com",
  });

  await waitFor(() => !app.$("#member-dialog").open);
});

test("an email already used by another member is shown in French when editing", async () => {
  const app = await mountApp({
    "GET /members": [camille],
    "PUT /members/m1": [
      409,
      { error: true, reason: "A member with this email already exists" },
    ],
  }, { hash: "#members" });

  await waitFor(() => app.$$("#members-list .row").length === 1);

  app.click("Modifier", app.$("#members-list .row")[0]);

  const form = app.$("#member-form");
  form.elements.email.value = "autre@example.com";
  form.requestSubmit();

  await waitFor(
    () => !app.$("#member-dialog .form-error").hidden,
    "le message d'erreur",
  );

  assertIncludes(
    app.$("#member-dialog .form-error").textContent,
    "utilise déjà cette adresse e-mail",
  );

  assertTrue(app.$("#member-dialog").open, "le formulaire devrait rester ouvert");
});

test("deleting a member asks for confirmation then sends DELETE", async () => {
  const app = await mountApp({
    "GET /members": [camille],
    "DELETE /members/m1": [204],
  }, { hash: "#members" });

  await waitFor(() => app.$$("#members-list .row").length === 1);

  app.click("Supprimer", app.$("#members-list .row")[0]);

  await waitFor(() => app.$("#delete-member-dialog").open);

  assertIncludes(app.$("#delete-member-message").textContent, "Camille");

  app.$("#delete-member-form").requestSubmit();

  await waitFor(
    () => app.calls.some((call) => call.method === "DELETE" && call.path === "/members/m1"),
    "l'appel DELETE /members/m1",
  );

  await waitFor(() => !app.$("#delete-member-dialog").open);
});

// --- Consultation des emprunts d'un·e adhérent·e

test("a member can view their loans with the three statuses and game titles", async () => {
  const now = Date.now();
  const date = (offsetDays) => new Date(now + offsetDays * 24 * 60 * 60 * 1000).toISOString();

  const loans = [
    {
      id: "l1",
      gameID: "g1",
      memberID: "m1",
      borrowedAt: date(-10),
      dueAt: date(-5),
      returnedAt: date(-4),
    },
    {
      id: "l2",
      gameID: "g2",
      memberID: "m1",
      borrowedAt: date(-2),
      dueAt: date(5),
      returnedAt: null,
    },
    {
      id: "l3",
      gameID: "g3",
      memberID: "m1",
      borrowedAt: date(-8),
      dueAt: date(-1),
      returnedAt: null,
    },
  ];

  const app = await mountApp({
    "GET /members": [camille],
    "GET /members/m1/loans": loans,
    "GET /games": [
      catan,
      dixit,
      {
        id: "g3",
        title: "Azul",
        minPlayers: 2,
        maxPlayers: 4,
        durationMinutes: 45,
        isAvailable: false,
      },
    ],
  }, { hash: "#members" });

  await waitFor(() => app.$$("#members-list .row").length === 1);

  app.click("Voir les emprunts", app.$("#members-list .row")[0]);

  await waitFor(() => app.$("#member-loans-dialog").open, "la boîte des emprunts");
  await waitFor(() => app.$$("#member-loans-list .loan-row").length === 3, "les trois emprunts");

  const content = app.$("#member-loans-list").textContent;

  assertIncludes(content, "Catan");
  assertIncludes(content, "Dixit");
  assertIncludes(content, "Azul");

  assertIncludes(content, "Rendu");
  assertIncludes(content, "En cours");
  assertIncludes(content, "En retard");

  assertTrue(
    app.calls.some((call) => call.method === "GET" && call.path === "/members/m1/loans"),
    "la liste des emprunts de Camille devrait être chargée",
  );
});

test("viewing a member's loans shows a message when there are none", async () => {
  const app = await mountApp({
    "GET /members": [camille],
    "GET /members/m1/loans": [],
    "GET /games": [],
  }, { hash: "#members" });

  await waitFor(() => app.$$("#members-list .row").length === 1);

  app.click("Voir les emprunts", app.$("#members-list .row")[0]);

  await waitFor(() => app.$("#member-loans-dialog").open, "la boîte des emprunts");
  await waitFor(
    () => !app.$("#member-loans-empty").hidden,
    "le message indiquant qu'il n'y a aucun emprunt",
  );

  assertIncludes(
    app.$("#member-loans-empty").textContent.toLowerCase(),
    "aucun emprunt",
  );

  assertEqual(
    app.$$("#member-loans-list .loan-row").length,
    0,
    "aucun emprunt ne devrait être affiché",
  );
});