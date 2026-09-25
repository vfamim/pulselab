import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The existing main-branch workflow builds before publishing to live Hosting.
// A test protocol must never pass that build, even after an accidental merge.
if (process.env.GITHUB_ACTIONS === "true" && process.env.GITHUB_REF === "refs/heads/main") {
  throw new Error("Test protocol v2 cannot be deployed to live Hosting.");
}

export default defineConfig({
  base: "/alunos/",
  plugins: [react()],
  build: {
    outDir: "../../alunos",
    emptyOutDir: true
  }
});
