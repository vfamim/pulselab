import React from "react";

export default class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null, showDetails: false };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    console.error("[PulseLab ErrorBoundary]", error, errorInfo);
  }

  handleReload = () => {
    window.location.reload();
  };

  handleResetAndReload = () => {
    try {
      // Limpar estados locais do PulseLab
      localStorage.removeItem("pulselab_student_active_session_v1");
      localStorage.removeItem("pulselab_simulator_active_session");
      if ("serviceWorker" in navigator) {
        navigator.serviceWorker.getRegistrations().then((registrations) => {
          registrations.forEach((r) => r.unregister());
        });
      }
      if ("caches" in window) {
        caches.keys().then((keys) => {
          keys.forEach((k) => caches.delete(k));
        });
      }
    } catch (e) {
      console.warn("Falha ao limpar armazenamento:", e);
    }
    window.location.href = window.location.pathname;
  };

  render() {
    if (this.state.hasError) {
      return (
        <main
          style={{
            fontFamily: "system-ui, -apple-system, sans-serif",
            minHeight: "100vh",
            background: "#070612",
            color: "#f8fafc",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            padding: "24px"
          }}
        >
          <div
            style={{
              maxWidth: "560px",
              width: "100%",
              background: "#111024",
              border: "1px solid #dc2626",
              borderRadius: "16px",
              padding: "32px",
              boxShadow: "0 20px 40px rgba(0,0,0,0.6)",
              textAlign: "center"
            }}
          >
            <div style={{ fontSize: "48px", marginBottom: "16px" }}>⚠️</div>
            <h1
              style={{
                fontSize: "1.5rem",
                margin: "0 0 12px",
                color: "#f87171",
                fontWeight: 800
              }}
            >
              Não foi possível carregar a oficina
            </h1>
            <p
              style={{
                fontSize: "1rem",
                color: "#94a3b8",
                lineHeight: 1.5,
                margin: "0 0 24px"
              }}
            >
              Ocorreu uma falha inesperada na interface. Os registros do robô e
              respostas anteriores continuam gravados com segurança no
              dispositivo.
            </p>

            <div
              style={{
                display: "flex",
                flexDirection: "column",
                gap: "12px",
                marginBottom: "20px"
              }}
            >
              <button
                onClick={this.handleReload}
                style={{
                  background: "#0284c7",
                  color: "#ffffff",
                  border: "none",
                  borderRadius: "10px",
                  padding: "12px 20px",
                  fontSize: "1rem",
                  fontWeight: 700,
                  cursor: "pointer"
                }}
              >
                🔄 Recarregar Página
              </button>

              <button
                onClick={this.handleResetAndReload}
                style={{
                  background: "rgba(220, 38, 38, 0.15)",
                  color: "#fca5a5",
                  border: "1px solid rgba(220, 38, 38, 0.4)",
                  borderRadius: "10px",
                  padding: "12px 20px",
                  fontSize: "0.95rem",
                  fontWeight: 600,
                  cursor: "pointer"
                }}
              >
                ✨ Limpar Dados Locais e Reiniciar Oficina
              </button>
            </div>

            <button
              onClick={() =>
                this.setState((prev) => ({ showDetails: !prev.showDetails }))
              }
              style={{
                background: "transparent",
                border: "none",
                color: "#64748b",
                fontSize: "0.85rem",
                cursor: "pointer",
                textDecoration: "underline"
              }}
            >
              {this.state.showDetails
                ? "Ocultar detalhes técnicos"
                : "Ver detalhes técnicos"}
            </button>

            {this.state.showDetails && this.state.error ? (
              <pre
                style={{
                  marginTop: "16px",
                  textAlign: "left",
                  background: "#0a0915",
                  padding: "12px",
                  borderRadius: "8px",
                  fontSize: "0.8rem",
                  color: "#f87171",
                  overflowX: "auto"
                }}
              >
                {this.state.error.toString()}
                {"\n"}
                {this.state.error.stack}
              </pre>
            ) : null}
          </div>
        </main>
      );
    }

    return this.props.children;
  }
}
