import { readFile, stat } from "node:fs/promises";
import { resolve, sep } from "node:path";
import type { FastifyInstance } from "fastify";

const CONTENT_TYPES: Record<string, string> = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".map": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

function contentType(path: string): string {
  const extension = path.slice(path.lastIndexOf(".")).toLowerCase();
  return CONTENT_TYPES[extension] ?? "application/octet-stream";
}

function safePath(root: string, pathname: string): string | null {
  let decodedPath: string;
  try {
    decodedPath = pathname.split("/").map((segment) => decodeURIComponent(segment)).join("/");
  } catch {
    return null;
  }
  const rootPath = resolve(root);
  const candidate = resolve(rootPath, "." + decodedPath);
  if (candidate !== rootPath && !candidate.startsWith(rootPath + sep)) return null;
  return candidate;
}

export function registerFrontendRoutes(app: FastifyInstance, clientDistDir: string): void {
  const root = resolve(clientDistDir);

  app.get("/*", async (request, reply) => {
    const pathname = new URL(request.url, "http://localhost").pathname;
    if (pathname === "/ws" || pathname.startsWith("/auth/") || pathname.startsWith("/world/") ||
      pathname.startsWith("/shop/") || pathname === "/health" || pathname === "/ready" ||
      pathname === "/metrics" || pathname.startsWith("/documentation")) {
      return reply.code(404).send({ error: "NOT_FOUND" });
    }

    const requested = safePath(root, pathname);
    if (!requested) return reply.code(400).send({ error: "INVALID_PATH" });

    let filePath = requested;
    try {
      const info = await stat(filePath);
      if (!info.isFile()) filePath = resolve(root, "index.html");
    } catch {
      filePath = resolve(root, "index.html");
    }

    try {
      const body = await readFile(filePath);
      const isAsset = filePath !== resolve(root, "index.html");
      reply.type(contentType(filePath));
      if (isAsset) reply.header("cache-control", "public, max-age=31536000, immutable");
      else reply.header("cache-control", "no-cache");
      return reply.send(body);
    } catch {
      return reply.code(404).send({ error: "FRONTEND_NOT_BUILT" });
    }
  });
}
