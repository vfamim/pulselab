import "./globals.css";

export const metadata = {
  title: "PulseLab — Simulador do Agente",
  description: "Versão web para validação pedagógica e operacional do agente PulseLab 1.6.0."
};

export default function RootLayout({ children }) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
