import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  base: "/simulador/",
  plugins: [react()],
  build: {
    outDir: "../../simulador",
    emptyOutDir: true
  }
});

