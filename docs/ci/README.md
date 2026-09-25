# Automação proposta, ainda inativa

`research-v2-test.workflow.yml` é uma proposta de workflow, não uma execução de CI.
O push inicial foi recusado porque a credencial disponível não tem escopo
`workflow`. Para não ampliar permissões, o PR inclui o pacote compilado e
seu SHA-256 em `test-packages/` e mantém a proposta fora de `.github/workflows`.

Um mantenedor com a permissão adequada pode revisar e copiar o arquivo para
`.github/workflows/research-v2-test.yml`. A proposta não usa credenciais de
produção nem aplica migrações remotamente. Ela executa testes unitários,
navegador, RLS em container descartável e smoke test no Windows PowerShell 5.1,
depois disponibiliza o pacote como artefato temporário.

Verificação local em 25/09/2026: 19 testes unitários, 12 de navegador e 17 SQL/RLS
passaram. O smoke test do servidor passou em PowerShell 7.4/Linux em container
sem rede externa. Isso não substitui executar o inicializador no Windows 10/11.
O bloqueio de build com `GITHUB_ACTIONS=true GITHUB_REF=refs/heads/main` também
foi verificado: impede que o workflow live existente publique esta versão.
