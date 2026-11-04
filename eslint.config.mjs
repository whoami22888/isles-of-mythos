import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: [
      "**/node_modules/**",
      "**/dist/**",
      "**/coverage/**",
      "**/.vite/**",
      "**/build/**",
    ],
  },
  {
    files: ["client/src/**/*.ts", "server/src/**/*.ts"],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommendedTypeChecked,
    ],
    languageOptions: {
      parserOptions: {
        projectService: true,
      },
    },
  },
  {
    // Root-level and scripts/** Node tooling (.mjs) has no tsconfig project
    // and must not fall through to "no matching config found" for
    // Codacy's ESLint adapter, which reports that as ConfigurationNotFoundError.
    files: ["scripts/**/*.mjs", "*.mjs"],
    extends: [js.configs.recommended],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: {
        // Node.js runtime globals used by these scripts. Scoped here instead
        // of pulling in the `globals` package as a new dependency.
        process: "readonly",
        console: "readonly",
        Buffer: "readonly",
        performance: "readonly",
        fetch: "readonly",
        structuredClone: "readonly",
        setTimeout: "readonly",
        clearTimeout: "readonly",
        setInterval: "readonly",
        clearInterval: "readonly",
        URL: "readonly",
        TextEncoder: "readonly",
        TextDecoder: "readonly",
        __dirname: "readonly",
        __filename: "readonly",
        module: "readonly",
        require: "readonly",
      },
    },
  },
);
