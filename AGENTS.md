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
   A versão corrente deve estar rigorosamente idêntica em todas as superfícies operacionais do ecossistema PulseLab. `VERSION` (raiz) é a fonte única.

   Superfícies com o número escrito, atualizadas por `tooling/release/bump-version.py`:
   - `package.json` e `package-lock.json` pertinentes (raiz e `apps/student-pwa/`);
   - `version.json` (canal legado com `auto_update_enabled: true`, usado só para máquinas até 2.2.7 migrarem ao atualizador assinado);
   - `config/defaults.json` (`client_version`) e `config/config.json` (`version`);
   - Bridge Local Windows (`runtime/windows/bridge/pulselab-bridge.ps1` na variável `$script:BridgeVersion` e rota `/v1/config`);
   - Launcher Portátil (`runtime/windows/pulselab.ps1` no fallback `$localVersion`);
   - Instalador (`runtime/windows/Instalar-PulseLab.bat` no título).

   Superfícies que recebem a versão no build pelo marcador `__PULSELAB_VERSION__` e nunca devem ter o número escrito à mão:
   - Interface do Usuário PWA (`apps/student-pwa/app/student-page.jsx`, `CLIENT_VERSION` e rodapé) e Service Worker (`apps/student-pwa/public/sw.js`, `CACHE_NAME`), via `apps/student-pwa/vite.config.js`. O build vai para `alunos/`, que não é versionado;
   - Páginas públicas (`apps/site/`: `index.html`, `instalador/`, `testes/` e `relatorio/`), via `tooling/site/build-hosting.py`;
   - Empacotamento (`tooling/release/build-installer.py`, `tooling/release/build-offline-package.sh` e `tooling/site/Atualizar-Site-Firebase.bat`), que leem `VERSION`.

   Os pacotes binários (`PulseLab-X.Y.Z-Windows.zip` e `.sha256`) são publicados como assets da Release `vX.Y.Z` no GitHub e não são versionados no git; não existe mais o ZIP `PulseLab-Alunos-Offline`. O guia do instrutor (`docs/campo/guia-instrutor.md`, gerado em `apps/site/tutorial/`) não cita a versão exata.

3. **Bloqueio Fail-Closed contra Versões Divergentes**:
   - Nenhum deploy pode prosseguir se houver discrepância entre as superfícies operacionais.
   - O repositório mantém um verificador automatizado de consistência (`tooling/release/check-version-consistency.py` e testes unitários) que faz a integração contínua (CI) e a suíte de testes falharem imediatamente perante qualquer divergência.

4. **Tratamento de Documentos Históricos vs. Operacionais**:
   - Documentos históricos legítimos (atas, relatórios passados como `relatorio-academico-metricas-pulselab-v1.4.md`, matrizes de revisão histórica ou referências metodológicas imutáveis) **não devem** ser reescritos retrospectivamente.
   - Páginas públicas, downloads, tutoriais de uso e artefatos operacionais em produção **devem** sempre refletir a versão corrente ativa.

---

## 2. Salvaguardas Éticas e Conformidade LGPD (Art. 14)

1. **Proteção a Menores**:
   - Nunca capture, processe ou armazene nomes, fotos, vídeos, áudios, endereços IP externos ou identificadores individuais de crianças.
   - A unidade de análise da pesquisa é a **bancada coletiva** (`group_id`), nunca o estudante isolado.

2. **Coleta Desligada por Padrão**:
   - O pacote genérico e os arquivos `config/*.json` nunca ligam a coleta de pesquisa (`research_collection_enabled: false`).
   - A coleta só é ativada por `provisionamento.json` do polo, gerado por `tooling/polo/gerar-pacote-polo.py` com CAAE no formato oficial, e gravado em `dados_locais/installation.json`.
   - Máquinas são identificadas por `installation_id` aleatório e rótulo escolhido na instalação; nome do computador, usuário do Windows e caminhos pessoais não são gravados nem exportados.

3. **Assentimento Verbal, Livre e Não-Punitivo** (desde a 2.4.0):
   - No início de cada aula o instrutor lê o roteiro padronizado de `docs/campo/assentimento-verbal.md`: o que é registrado, que a participação é voluntária e que qualquer pessoa pode recusar a qualquer momento, sem consequência. As famílias são informadas antes, conforme o TCLE aprovado pelo CEP.
   - Nenhuma tela de assentimento, questionário, contador ou alerta aparece para as crianças durante a aula; o PulseLab fica só como ícone na bandeja.
   - A recusa de qualquer membro da bancada (ou da família) leva o instrutor a usar **"Não registrar esta turma"** no ícone da bandeja: a aula daquela turma é marcada imediatamente como não autorizada (dados nunca usados) e o registro pausa até a próxima aula, com acesso pedagógico integral às ferramentas de robótica. A exclusão definitiva é feita na revisão do pesquisador.

4. **Retenção Local Configurável e Retirada Imediata**:
   - Dados locais do Bridge expiram no prazo `retention_days` do provisionamento do polo (1 a 365 dias), com padrão de 180 dias (`Invoke-BridgeRetentionCleanup`). Desde a 2.4.0 o navegador não guarda dados (o formulário final apaga o IndexedDB das versões antigas). O prazo deve constar no protocolo e no TCLE aprovados pelo CEP.
   - A cópia local permanece no computador durante todo o prazo, mesmo depois do envio à nuvem ou da exportação.
   - "Não registrar esta turma" executa a marcação imediata como não autorizada (dados nunca usados) e exclusão definitiva na revisão do pesquisador, com tombstone contra reenvio (na tabela `research_withdrawals`, que também barra reimportação por pendrive). Não há prazo automático para apagar: polos sem internet entregam pendrive meses depois. A marca vai junto com a sessão (`authorization_status = "nao_autorizada"`) e toda view de análise ou de qualidade filtra com `research_session_is_authorized(session_id)`.

5. **Proibição de Telemetria Invasiva**:
   - Captura de tela (screenshots) e interceptação global de teclas (`GetAsyncKeyState`) são terminantemente proibidas e abolidas.

---

## 3. Segurança Técnica e Diretrizes Operacionais

1. **Preservação de Segredos**:
   - Nunca inspecione, exiba ou comite arquivos `.env`, tokens JWT operacionais, chaves privadas, senhas ou service role keys do Supabase.

2. **Compatibilidade com Windows PowerShell 5.1**:
   - Mantenha a terminação de linha **CRLF** (`\r\n`) em todos os scripts PowerShell (`.ps1`).
   - Não utilize métodos incompatíveis do .NET Core como `[System.IO.File]::Replace($src, $dst, $null)` sem backup; utilize a rotina segura `Move-BridgeAtomicFile`.
   - Não atribua valores a variáveis automáticas reservadas do PowerShell como `$PID`.

3. **Atualização Automática Assinada**:
   - O launcher consulta apenas o manifesto `pulselab-update.json` da última release publicada no GitHub, com timeout de 2 segundos, e só quando o servidor local não está em execução.
   - O manifesto deve estar assinado (RSA-SHA256) pela chave privada do projeto, guardada fora do repositório. Sem `release-public-key.json` ou com assinatura inválida, não há atualização.
   - O ZIP é conferido pelo SHA-256 do manifesto assinado, validado (sintaxe dos scripts) e instalado por troca de pastas com backup em `_update_backup`. Se o servidor local não iniciar, a versão anterior é restaurada e a nova fica bloqueada naquela máquina.
   - `dados_locais/` e `provisionamento.json` nunca são movidos, apagados ou sobrescritos.
   - Releases são publicadas com `tooling/release/publicar-release.py`; pré-releases não chegam às máquinas.

4. **Governança de Mudanças**:
   - Toda mudança entra na `main` por pull request com o CI verde (`.github/workflows/ci.yml`).
   - Agentes de IA não fazem push direto na `main` nem alteram este arquivo, `release-public-key.json`, o launcher, o atualizador ou `config/` sem revisão humana.
