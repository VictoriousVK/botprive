import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts", "src/register-commands.ts"],
  format: ["esm"],
  target: "node22",
  platform: "node",
  outDir: "dist",
  clean: true,
  sourcemap: true,
  // Bundle autonome : tout le code (monorepo + dépendances) dans dist/, image Docker minimale.
  noExternal: [/.*/],
  // Modules natifs optionnels de discord.js, non utilisés.
  external: ["zlib-sync", "bufferutil", "utf-8-validate", "erlpack"],
  // Certaines dépendances CommonJS appellent require() : on le fournit dans le bundle ESM.
  banner: { js: "import { createRequire as __createRequire } from 'node:module'; const require = __createRequire(import.meta.url);" },
});
