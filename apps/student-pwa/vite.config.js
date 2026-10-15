import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  base: "/alunos/",
  plugins: [react()],
  build: {
    outDir: "../../alunos",
    emptyOutDir: true
  }
});
