import "@fastify/jwt";

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: {
      sub: string;
      username: string;
      role?: "player" | "admin";
    };
    user: {
      sub: string;
      username: string;
      role?: "player" | "admin";
    };
  }
}
