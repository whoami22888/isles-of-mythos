const TOKEN_KEY = "isles-of-mythos.access-token";

interface AuthResponse { accessToken: string; }
export function getAccessToken(): string | null { return window.localStorage.getItem(TOKEN_KEY); }
function setAccessToken(token: string): void { window.localStorage.setItem(TOKEN_KEY, token); }

async function submitAuth(baseUrl: string, mode: "login" | "register", identifier: string, password: string, email: string): Promise<void> {
  const endpoint = mode === "login" ? "/auth/login" : "/auth/register";
  const body = mode === "login" ? { identifier, password } : { username: identifier, email, password };
  const response = await fetch(baseUrl + endpoint, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  const data = await response.json() as Partial<AuthResponse> & { message?: string };
  if (!response.ok || typeof data.accessToken !== "string") throw new Error(data.message ?? "Authentication failed (" + response.status + ")");
  setAccessToken(data.accessToken);
}

export async function ensureAuthenticated(): Promise<void> {
  if (getAccessToken()) return;
  const baseUrl = (import.meta.env.VITE_API_BASE_URL ?? "http://localhost:3000").replace(/\/$/, "");
  const container = document.getElementById("game");
  if (!container) throw new Error("Game container is missing");

  const overlay = document.createElement("div");
  overlay.style.cssText = "position:fixed;inset:0;display:grid;place-items:center;background:#07131f;color:#fff;font-family:system-ui,sans-serif;z-index:10000";
  const form = document.createElement("form");
  form.style.cssText = "width:min(420px,90vw);padding:28px;background:#102238;border:1px solid #31506e;border-radius:14px;box-shadow:0 18px 60px #0008";
  form.innerHTML = '<h1 style="margin:0 0 8px">Isles of Mythos</h1><p style="margin:0 0 20px;color:#b7c7d9">Create or load your persistent pirate.</p><label>Username / email<input name="identifier" required minlength="3" maxlength="254" style="display:block;width:100%;box-sizing:border-box;margin:6px 0 12px;padding:10px"></label><label class="email-label" style="display:none">Email<input name="email" type="email" maxlength="254" style="display:block;width:100%;box-sizing:border-box;margin:6px 0 12px;padding:10px"></label><label>Password<input name="password" type="password" required minlength="12" maxlength="128" style="display:block;width:100%;box-sizing:border-box;margin:6px 0 12px;padding:10px"></label><button name="submit" type="submit" style="width:100%;padding:11px">Login</button><button name="toggle" type="button" style="width:100%;padding:11px;margin-top:8px">Create account</button><p class="error" style="min-height:20px;color:#ff9b9b"></p>';
  overlay.appendChild(form); container.appendChild(overlay);

  const emailLabel = form.querySelector(".email-label") as HTMLElement;
  const submit = form.querySelector("[name=submit]") as HTMLButtonElement;
  const toggle = form.querySelector("[name=toggle]") as HTMLButtonElement;
  const error = form.querySelector(".error") as HTMLElement;
  let mode: "login" | "register" = "login";

  toggle.addEventListener("click", () => {
    mode = mode === "login" ? "register" : "login";
    emailLabel.style.display = mode === "register" ? "block" : "none";
    submit.textContent = mode === "register" ? "Create account" : "Login";
    toggle.textContent = mode === "register" ? "Back to login" : "Create account";
    error.textContent = "";
  });

  await new Promise<void>((resolve) => {
    form.addEventListener("submit", async (event) => {
      event.preventDefault(); error.textContent = ""; submit.disabled = true;
      try {
        const data = new FormData(form);
        await submitAuth(baseUrl, mode, String(data.get("identifier") ?? ""), String(data.get("password") ?? ""), String(data.get("email") ?? ""));
        overlay.remove(); resolve();
      } catch (reason) {
        error.textContent = reason instanceof Error ? reason.message : "Authentication failed";
        submit.disabled = false;
      }
    });
  });
}
