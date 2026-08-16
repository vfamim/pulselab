// PulseLab - Configuração Pública do Portal do Instrutor
// Copie este arquivo para 'config.js' no mesmo diretório ('instrutor/config.js') e preencha as variáveis do projeto.
// IMPORTANTE: Nunca inclua a service_role key, senhas ou tokens administrativos neste arquivo.
// Apenas a URL do Supabase e a anon public key são permitidas no cliente web.

window.PULSELAB_INSTRUCTOR_CONFIG = {
  supabaseUrl: "https://SEU-PROJETO.supabase.co",
  supabaseAnonKey: "SUA-ANON-PUBLIC-KEY",
  // O modo de demonstração local é desabilitado por padrão para garantir a autenticação de campo
  allowDemo: false
};
