# Guia de Contribuição do PulseLab

Seja bem-vindo(a) ao projeto **PulseLab**! Este documento orienta pesquisadores, alunos bolsistas e desenvolvedores da comunidade sobre como colaborar com o projeto de forma ética, segura e padronizada.

---

## 1. Sobre o PulseLab

O **PulseLab** é a camada de observação científica das oficinas do projeto de extensão e pesquisa em Robótica Educativa da UNIVASF. Ele opera em computadores de escolas públicas (Windows) de forma silenciosa e não intrusiva, registrando o progresso das bancadas de alunos com kits LEGO SPIKE e oferecendo uma interface opcional de questionário de percepção ao final das aulas.

---

## 2. 🛡️ Salvaguardas Éticas Invioláveis (LGPD Art. 14 / CEP)

Todo código ou funcionalidade proposta deve cumprir rigorosamente o protocolo aprovado pelo Comitê de Ética em Pesquisa (CEP) e o Artigo 14 da Lei Geral de Proteção de Dados (LGPD):

1. **Proteção a Menores**:
   - É terminantemente proibido capturar, processar ou armazenar nomes, fotos, vídeos, áudios, endereços IP externos ou quaisquer identificadores nominais diretos de crianças e adolescentes.
   - A unidade de análise da pesquisa é a **bancada coletiva** (`group_id`), nunca o estudante isolado.
2. **Sem Telemetria Invasiva**:
   - Capturas de tela (screenshots) e monitoramento global de teclas digitadas (`GetAsyncKeyState`, keyloggers) são proibidos no ecossistema do PulseLab.
3. **Assentimento Verbal e Não-Punitivo**:
   - A participação de estudantes nas pesquisas é estritamente voluntária. O questionário de encerramento (`/alunos/`) é opcional e todas as perguntas contam com a opção "Não quero responder".
   - A recusa de qualquer membro da bancada aciona o mecanismo "Não registrar esta turma" pelo instrutor, descartando os dados daquela oficina sem qualquer prejuízo pedagógico.
4. **Preservação de Segredos e Isolamento de Dados**:
   - Nunca comite arquivos `.env`, chaves privadas, service role keys do Supabase ou arquivos reais de telemetria coletados em escolas (`dados_locais/`, dumps SQLite).

---

## 3. Fluxo de Trabalho Git e Política de Branches

O repositório adota governança estrita para proteger a estabilidade dos softwares em execução nas escolas:

1. **`main` é uma branch protegida**:
   - Nenhum desenvolvedor pode fazer push direto para a branch `main`.
   - Todas as modificações entram exclusivamente via **Pull Request (PR)**.
2. **Aprovações Obrigatórias**:
   - Todo PR requer no mínimo **1 aprovação** de um revisor do projeto.
   - Arquivos do núcleo de execução nas escolas (`runtime/windows/`, `config/`, chaves criptográficas e regras operacionais) estão sob a governança de [CODEOWNERS](.github/CODEOWNERS) e exigem aprovação mandatória do pesquisador responsável (`@vfamim`).
3. **Nomenclatura de Branches**:
   Crie branches temáticas a partir da `main` atualizada:
   - `feat/nome-da-funcionalidade` para novos recursos;
   - `fix/descricao-da-correcao` para correções de bugs;
   - `docs/melhoria-na-documentacao` para manuais e documentações;
   - `test/novos-testes` para suítes de validação.

---

## 4. Ambiente de Desenvolvimento e Validação Local

### Pré-requisitos
- **Node.js** 20 LTS ou superior;
- **Python** 3.11 ou superior;
- **PowerShell** 5.1 (Windows) ou **PowerShell Core (pwsh)** (Linux/macOS);
- **Git**.

### Instalação das Dependências
```bash
# Na raiz do repositório
npm install

# No PWA dos alunos
cd apps/student-pwa
npm install
cd ../..
```

### Rodando os Testes Automatizados Antes de Abrir PR
Antes de submeter suas alterações, execute as suítes de teste locais:

```bash
# 1. Testes unitários do frontend PWA
cd apps/student-pwa
npm run test:unit
cd ../..

# 2. Testes de unidade em Python (Bridge, telemetria, relatórios)
python3 -m unittest discover -s tests/python -p 'test_*.py'

# 3. Verificação de consistência de versão
python3 tooling/release/check-version-consistency.py

# 4. Sintaxe dos scripts PowerShell
pwsh -Command 'Get-ChildItem -Recurse -Include *.ps1 | ForEach-Object { [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors); if ($errors) { Write-Error "$($_.FullName): $($errors[0].Message)" } }'
```

---

## 5. Regras Técnicas para Scripts Windows

1. **Terminação de Linha CRLF**:
   - Todos os scripts PowerShell (`.ps1`) e arquivos de lote (`.bat`) devem obrigatoriamente manter terminação de linha **CRLF** (`\r\n`), para compatibilidade total com o Windows PowerShell 5.1 dos computadores de laboratório.
2. **Codificação ASCII nos Arquivos `.bat`**:
   - Scripts `.bat` (como `Instalar-PulseLab.bat`) devem evitar acentuação direta em caixas de diálogo DOS ou utilizar codificação compatível com o prompt de comando legados.
3. **Escrita Atômica de Arquivos**:
   - Utilize a rotina segura `Move-BridgeAtomicFile` ao gravar arquivos de estado local no Windows para evitar corrupção durante desligamentos abruptos das máquinas.

---

## 6. Propondo Sugestões e Novos Casos de Uso

Tem uma sugestão de dinâmica para a sala de aula, novo tipo de sensor ou melhoria para os instrutores?
- Abra uma **[Issue de Sugestão / Caso de Uso](https://github.com/vfamim/pulselab/issues/new/choose)** descrevendo o contexto da escola ou polo, os benefícios pedagógicos esperados e os impactos operacionais.
- Para discussões gerais ou alinhamentos de pesquisa, procure a equipe de coordenação do projeto no laboratório.
