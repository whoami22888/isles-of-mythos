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
);
