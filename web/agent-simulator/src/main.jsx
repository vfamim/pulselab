import React from "react";
import ReactDOM from "react-dom/client";
import StudentPage from "../app/student-page.jsx";
import "../app/globals.css";

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <StudentPage />
  </React.StrictMode>
);

if ("serviceWorker" in navigator && import.meta.env.PROD) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/alunos/sw.js").catch(() => {
      // O armazenamento local continua funcional mesmo se o service worker falhar.
    });
  });
}
