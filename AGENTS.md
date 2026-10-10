# Diretrizes Operacionais para Agentes de IA no Repositório PulseLab

Este documento estabelece as regras normativas, salvaguardas éticas e protocolos técnicos obrigatórios para qualquer agente de IA (Antigravity, Codex, Claude Code ou outro) que opere no repositório **PulseLab**.

---

## 1. Regra Permanente de Versionamento e Sincronização

Toda alteração que for enviada (commit), mesclada (merge) ou implantada (deploy) no PulseLab está sujeita às seguintes normas:

1. **Incremento Obrigatório Pré-Commit**:
   - Nenhuma alteração destinada a publicação ou deploy pode ser commitada sem que a versão do projeto tenha sido formalmente incrementada.
   - O padrão para correções de bugs, ajustes de persistência e melhorias operacionais é o incremento de **PATCH** (ex.: `2.1.0` -> `2.2.0` ou `2.2.0` -> `2.2.1`).
   - Incrementos de **MINOR** ou **MAJOR** devem ocorrer quando houver acréscimo de novas capacidades metodológicas, alterações de quebra de compatibilidade ou quando solicitado explicitamente pelo pesquisador responsável.

2. **Sincronização Canônica Obrigatória em Todas as Superfícies**:
   A versão corrente deve estar rigorosamente idêntica em todas as superfícies operacionais do ecossistema PulseLab:
   - `VERSION` (arquivo canônico de referência na raiz do repositório);
   - `package.json` e `package-lock.json` pertinentes (raiz e `web/agent-simulator/`);
   - `version.json` (com `auto_update_enabled: true`);
   - `config/defaults.json` (`client_version`) e `config/config.json` (`version`);
   - Interface do Usuário PWA (`web/agent-simulator/app/student-page.jsx` no cabeçalho/rodapé e constante `CLIENT_VERSION`);
   - Bridge Local Windows (`bridge/pulselab-bridge.ps1` na variável `$script:BridgeVersion` e rota `/v1/config`);
   - Launcher Portátil (`pulselab.ps1` no fallback `$localVersion`);
   - Service Worker (`web/agent-simulator/public/sw.js` e `alunos/sw.js` no `CACHE_NAME`);
   - Scripts de empacotamento (`installer/build-installer.py` na constante `VERSION` e `scripts/build-offline-package.sh`);
   - Importador e consolidador (`scripts/importar-para-supabase.py` nos defaults de versão);
   - Scripts em lote (`Instalar-PulseLab.bat` e `Atualizar-Site-Firebase.bat`);
   - Nomes dos pacotes binários distribuíveis e checksums (`PulseLab-X.Y.Z-Windows.zip`, `.sha256`, `PulseLab-Alunos-Offline-vX.Y.Z.zip`);
   - Páginas públicas e documentação operacional (`index.html`, `instalador/index.html`, `testes/index.html`, `tutorial/index.html`, `relatorio/index.html`).

3. **Bloqueio Fail-Closed contra Versões Divergentes**:
   - Nenhum deploy pode prosseguir se houver discrepância entre as superfícies operacionais.
   - O repositório mantém um verificador automatizado de consistência (`scripts/check-version-consistency.py` e testes unitários) que faz a integração contínua (CI) e a suíte de testes falharem imediatamente perante qualquer divergência.

4. **Tratamento de Documentos Históricos vs. Operacionais**:
   - Documentos históricos legítimos (atas, relatórios passados como `relatorio-academico-metricas-pulselab-v1.4.md`, matrizes de revisão histórica ou referências metodológicas imutáveis) **não devem** ser reescritos retrospectivamente.
   - Páginas públicas, downloads, tutoriais de uso e artefatos operacionais em produção **devem** sempre refletir a versão corrente ativa.

---

## 2. Salvaguardas Éticas e Conformidade LGPD (Art. 14)

1. **Proteção a Menores**:
   - Nunca capture, processe ou armazene nomes, fotos, vídeos, áudios, endereços IP externos ou identificadores individuais de crianças.
   - A unidade de análise da pesquisa é a **bancada coletiva** (`group_id`), nunca o estudante isolado.

2. **Assentimento Livre e Não-Punitivo**:
   - Os termos de assentimento na tela inicial iniciam desmarcados.
   - A recusa de qualquer membro ativa o **Modo Livre**, garantindo acesso pedagógico integral às ferramentas de robótica sem gravação de pesquisa e sem envio de dados.

3. **Retenção Estrita de 7 Dias e Retirada Imediata**:
   - Dados locais no IndexedDB e no Bridge expiram em no máximo 7 dias (`enforceAbsoluteRetention` e `Invoke-BridgeRetentionCleanup`).
   - O botão "Parar de participar e apagar meus dados" executa o expurgo definitivo e imediato dos dados locais, registra tombstone contra reenvio e executa exclusão remota autenticada com retry.

4. **Proibição de Telemetria Invasiva**:
   - Captura de tela (screenshots) e interceptação global de teclas (`GetAsyncKeyState`) são terminantemente proibidas e abolidas.

---

## 3. Segurança Técnica e Diretrizes Operacionais

1. **Preservação de Segredos**:
   - Nunca inspecione, exiba ou comite arquivos `.env`, tokens JWT operacionais, chaves privadas, senhas ou service role keys do Supabase.

2. **Compatibilidade com Windows PowerShell 5.1**:
   - Mantenha a terminação de linha **CRLF** (`\r\n`) em todos os scripts PowerShell (`.ps1`).
   - Não utilize métodos incompatíveis do .NET Core como `[System.IO.File]::Replace($src, $dst, $null)` sem backup; utilize a rotina segura `Move-BridgeAtomicFile`.
   - Não atribua valores a variáveis automáticas reservadas do PowerShell como `$PID`.

3. **Atualização Automática Verificada e Resiliente (SHA-256)**:
   - O PulseLab executa verificação de atualização leve e silenciosa na inicialização quando houver conectividade com a internet, utilizando timeout fail-safe de 2 segundos para nunca travar em escolas offline.
   - Todo pacote recebido é estritamente validado contra o checksum criptográfico SHA-256 oficial antes da extração.
   - Preservação total de dados: a pasta `dados_locais/` é estritamente preservada contra sobrescrita durante qualquer atualização.
