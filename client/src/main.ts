import { ensureAuthenticated } from "./auth.js";

void ensureAuthenticated()
  .then(async () => {
    const { startGame } = await import("./game.js");
    startGame();
  })
  .catch((error) => {
    const game = document.getElementById("game");
    if (game) game.textContent = error instanceof Error ? error.message : "Authentication failed";
  });
