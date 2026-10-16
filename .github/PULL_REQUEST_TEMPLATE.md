## Descrição das Alterações

<!-- Descreva de forma clara e objetiva o que esta alteração faz, por que ela é necessária e qual problema resolve. -->

## Tipo de Alteração

- [ ] 🚀 Nova funcionalidade (`feat`)
- [ ] 🐛 Correção de bug (`fix`)
- [ ] 📝 Documentação (`docs`)
- [ ] ♻️ Refatoração de código (`refactor`)
- [ ] ⚙️ Ajustes de CI / build / release (`chore` ou `ci`)
- [ ] 🧪 Testes automatizados (`test`)

## 🛡️ Salvaguardas Éticas e Conformidade LGPD (Art. 14 / CEP)

Marque todas as caixas para confirmar que as diretrizes éticas foram respeitadas:

- [ ] **Proteção a Menores**: A alteração **NÃO** coleta, processa nem expõe nomes, fotos, vídeos, áudios, endereços IP externos ou identificadores individuais de crianças.
- [ ] **Unidade de Análise**: A unidade de observação continua sendo a bancada coletiva (`group_id`).
- [ ] **Sem Telemetria Invasiva**: Não foram adicionadas capturas de tela, gravação de teclas (`GetAsyncKeyState`) ou monitoramento periférico não autorizado.
- [ ] **Sem Vazamento de Segredos**: Nenhum arquivo `.env`, credencial do Supabase, token JWT ou chave privada foi incluído no commit.
- [ ] **Sem Dados Locais**: Nenhuma base SQLite real, pasta `dados_locais/` ou arquivo de telemetria de polos foi adicionado.

## 🧪 Verificações Técnicas

- [ ] **Testes Locais Aprovados**:
  - [ ] `cd apps/student-pwa && npm run test:unit`
  - [ ] `python3 -m unittest discover -s tests/python -p 'test_*.py'`
- [ ] **Consistência de Versão**:
  - Se esta alteração altera superfícies de produção, a versão foi incrementada via `python3 tooling/release/bump-version.py` e verificada com `python3 tooling/release/check-version-consistency.py`.
- [ ] **Compatibilidade Windows**:
  - Arquivos PowerShell (`.ps1`) e Batch (`.bat`) preservaram a terminação de linha **CRLF** (`\r\n`) e codificação adequada.

## Issue Relacionada

Fixes # <!-- ou "Relacionado a #" -->
