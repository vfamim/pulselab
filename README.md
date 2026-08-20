# Pulselab

Fundação de observação distribuída e controle de qualidade para oficinas de robótica escolar. O agente coleta autorrelatos pseudonimizados, evidências técnicas minimizadas e uma linha do tempo auditável de cada sessão realizada com kits LEGO SPIKE.

---

## Novidades da Versão 1.5.0

- **Autenticação individual por dispositivo**: cada máquina usa JWT próprio, vinculado por RLS a `auth.uid()`, `installation_id` e `site_id`.
- **Enrollment de uso único**: o coordenador emite um token aleatório com expiração; a Edge Function o consome antes de criar a conta do dispositivo.
- **Segredos protegidos no Windows**: access/refresh tokens ficam cifrados por DPAPI em `%LOCALAPPDATA%\PulseLab\device_session.dat`.
- **Motor corrigido**: grupos solo, dupla e trio, troca de papéis, rubrica obrigatória e retomada com tempo absoluto estão no fluxo executável.
- **Fila offline robusta**: escrita atômica, mutex, quarentena e recuperação sem inflar cobertura acadêmica.
- **Portal real**: autenticação Supabase, whitelist ativa e persistência de avaliações vinculadas à sessão.
- **Instalador seguro**: pacote ZIP genérico, sem credenciais, sem pipe remoto e com manifestos SHA-256.
- **CI ampliada**: Windows PowerShell 5.1, contratos Python/Node, build web e pgTAP/RLS com Supabase local.

A versão 1.5.0 é uma atualização de segurança incompatível com a ingestão anônima anterior. Aplique as migrations e publique a Edge Function antes de matricular máquinas.

---

## Arquitetura do Repositório

```
pulselab/
├── agent/
│   └── pulselab-agent.ps1      # Daemon PowerShell WPF (coletor em background e interfaces)
├── config/
│   └── config.json             # Configuração remota GitOps (fonte de verdade no GitHub)
├── dashboard/
│   └── index.html              # Painel Analytics (Resultados, Metodologia, TCC e Coletor)
├── web/
│   └── agent-simulator/        # Simulador navegável do agente para Linux e validação
├── installer/
│   ├── build-installer.py      # Script Python para compilar o instalador único (Linux/macOS)
│   ├── build-installer.ps1     # Script PowerShell para compilar o instalador único (Windows)
│   └── setup-startup.ps1       # Setup manual via PowerShell por máquina
├── schema/
│   └── supabase-schema.sql     # DDL completo da tabela e bucket no Supabase
└── docs/
    ├── PLAN-pulselab-mvp.md    # Especificações históricas do MVP
    ├── protocolo-pesquisa-v1.md # Protocolo acadêmico e decisões pendentes
    ├── parecer-roadmap-observacao-distribuida.md # Parecer e roadmap de longo prazo
    ├── arquitetura-evidencias-v1.4.md # Contrato técnico do primeiro incremento
    ├── contexto-projeto-robotica-educativa.md # Contexto institucional público usado no front
    ├── validacao-simulador-web.md # Protocolo de validação do fluxo navegável
    ├── relatorio-metodologia-pulselab.html # Relatório navegável
    └── tcc-research-framework.md # Guia histórico do TCC
```

---

## Pré-requisitos

- Para o agente real: Windows 10 ou superior com PowerShell 5.1, um projeto
  configurado no [Supabase](https://supabase.com) e permissão de usuário padrão.
- Para o simulador: Linux, macOS ou Windows, Node.js e um navegador atual. O
  simulador não precisa de Supabase e não coleta dados reais.

## Simulador web no Linux

O fluxo da versão 1.5.0 pode ser percorrido no navegador sem uma máquina Windows:

```bash
cd web/agent-simulator
npm install
npm run dev
```

Acesse `http://localhost:3000`. A interface permite simular o fluxo padrão,
atraso de checkpoint, ausência do SPIKE e queda de rede, além de inspecionar os
eventos e exportar a sessão em JSON.

Essa versão valida a experiência do instrumento e seus contratos. Captura de
tela, detecção da janela do SPIKE, cache em disco, sincronização com Supabase e
integração Win32 continuam sendo responsabilidades do agente Windows. O roteiro
de avaliação está em
[`docs/validacao-simulador-web.md`](docs/validacao-simulador-web.md).

---

## Setup: Supabase

1. Acesse o painel do seu projeto no Supabase Studio.
2. Abra o **SQL Editor**.
3. Execute todo o conteúdo de `schema/supabase-schema.sql`. Isso irá:
   - Criar, sem apagar a tabela legada, a tabela `research_events`.
   - Criar `research_session_events` para a linha do tempo e controle de qualidade.
   - Criar a view protegida `research_session_quality` para o futuro backend do painel.
   - Adicionar os campos de rastreabilidade 1.5 a bancos já existentes.
   - Configurar `screenshots` como bucket privado.
   - Remover a política de leitura pública criada pela versão 1.2.
   - Conceder explicitamente apenas `INSERT` ao coletor com credenciais autenticadas; consultas e ingestão anônima não autorizada permanecem bloqueadas.

> RLS é uma salvaguarda técnica, mas não substitui consentimento, assentimento, minimização, controle de acesso e política de retenção.

---

## Setup: GitHub (GitOps)

1. Edite o arquivo `config/config.json`:
   - Defina `"site_id"` para a sede/cidade inicial ou informe-o ao gerar o instalador.
   - Insira o identificador regional em `"regional_hub"` (ex: `"Polo-Nordeste-01"`).
   - Defina os códigos padrão de escola, oficina e turma. Valores que ainda começarem com `CONFIGURE_` aparecerão vazios na primeira abertura.
   - Ajuste `activity_id` e as perguntas somente após aprovação da versão do protocolo.
   - Configure `"config_remote_url"` com a URL raw do seu repositório pessoal:
     ```
     https://raw.githubusercontent.com/vfamim/pulselab/main/config/config.json
     ```
2. Realize o commit e envie para a branch `main` ou de release ativa.

Sede, regional, escola, oficina, turma, atividade e tamanho do grupo são persistidos em `%LOCALAPPDATA%\PulseLab\installation.json` após a primeira confirmação válida. Na próxima execução, a preparação reaparece preenchida para conferência e edição. A confirmação das autorizações nunca é reutilizada: precisa ser marcada em cada oficina. Atualizações remotas do protocolo não substituem a identidade local da instalação.

---

## Instalação segura no Windows

O pacote público não contém URL privada, token de enrollment, senha ou chave administrativa. A instalação é por usuário porque o DPAPI vincula a sessão à conta do Windows.

### 1. Preparar o backend

1. Aplique as migrations de `supabase/migrations/`.
2. Publique `supabase/functions/enroll-device`.
3. Mantenha `SUPABASE_SERVICE_ROLE_KEY` somente nos secrets da Edge Function e no ambiente administrativo.
4. Emita um token por máquina com `supabase/scripts/provision_device.py`; nunca envie a chave administrativa ao computador da oficina.

### 2. Baixar e validar

- Site: `https://pulselab-robotica-edu.web.app/instalador/`
- GitHub Release: `https://github.com/vfamim/pulselab/releases/tag/v1.5.0`

```powershell
Get-FileHash .\PulseLab-1.5.0-Windows.zip -Algorithm SHA256
```

### 3. Instalar e matricular

1. Extraia todo o ZIP.
2. Execute `Instalar-PulseLab.bat` com dois cliques.
3. Informe URL, chave pública `anon`, sede, regional e escola.
4. Digite o token de enrollment no prompt mascarado.
5. Abra o atalho **Iniciar PulseLab - Oficina de Robótica**.

O aplicativo é instalado em `%LOCALAPPDATA%\PulseLab\App`. A sessão autenticada fica fora da pasta da aplicação para sobreviver a atualizações. Reexecutar o pacote atualiza o aplicativo, mas não reativa automaticamente um dispositivo revogado.

### Gerar o pacote reproduzível

```bash
python3 installer/build-installer.py \
  --output instalador/downloads/PulseLab-1.5.0-Windows.zip
```

```powershell
.\installer\build-installer.ps1 `
  -OutputPath .\instalador\downloads\PulseLab-1.5.0-Windows.zip
```

Os dois builders geram um ZIP sem segredos, `SHA256SUMS.txt` interno e um arquivo `.zip.sha256` externo.

---

## Como Usar na Oficina (Fluxo do Usuário)

1. O instrutor abre o atalho, revisa os dados operacionais pré-preenchidos e corrige o que mudou, sem nomes de estudantes.
2. O instrutor confirma que verificou as autorizações e o consentimento aplicáveis.
3. Cada criança recebe o convite de assentimento. Se qualquer uma recusar, o coletor encerra e a dupla continua normalmente na oficina.
4. As crianças respondem, separadamente, experiência prévia e autoeficácia.
5. A atividade recebe uma linha do tempo com heartbeats técnicos minimizados.
6. Aos **20 e 40 minutos absolutos**, cada participante responde sozinho sobre esforço mental e situação da dupla. A colaboração é perguntada aos 40 minutos por padrão.
7. Depois do minuto 20, o agente solicita e registra a troca dos papéis por padrão.
8. Se alguém selecionar “precisamos de ajuda agora”, o agente alerta o instrutor e registra o evento.
9. A captura opcional registra a região da tela correspondente à janela do SPIKE e é enviada ao bucket privado.
10. Problemas como atraso, ausência da janela do SPIKE ou falha de captura geram eventos de qualidade.
11. Depois do último checkpoint, o agente aguarda o instrutor selecionar **Concluir Oficina**.
12. O instrutor registra desempenho da missão, intervenções e dificuldade principal. Depois, cada participante responde compreensão, afetos e intenção de retorno.

---

## Comportamento de Conexão Offline

Caso ocorram oscilações na rede Wi-Fi escolar, respostas, eventos de sessão e imagens pendentes são armazenados em `%LOCALAPPDATA%\PulseLab\cache`. O agente tenta reenviá-los no checkpoint seguinte, na inicialização ou no encerramento. `event_id` torna o reenvio idempotente e evita duplicações.

O cache não deve ser copiado para outra máquina. Se uma máquina ficar offline durante toda a oficina, preserve o perfil local até que o agente consiga sincronizar os eventos.

## Atualização do agente

Para atualizar as máquinas:

1. Edite e valide o código/configuração na máquina de preparação.
2. Gere um novo instalador com a versão atualizada.
3. Execute o novo instalador em cada computador.
4. Teste uma oficina de homologação antes de distribuir para todas as escolas.

O agente carrega a configuração remota definida em `config_remote_url`, mas a configuração local deve continuar válida para funcionamento offline.

## Checklist antes da primeira oficina

- [ ] O schema `schema/supabase-schema.sql` foi executado no Supabase.
- [ ] O bucket `screenshots` está privado.
- [ ] A chave utilizada é `anon`, nunca `service_role`.
- [ ] O `.env` está apenas na máquina de preparação.
- [ ] O instalador standalone não foi adicionado ao Git.
- [ ] Uma máquina de teste recebeu o instalador com sucesso.
- [ ] O atalho **Iniciar Pulselab - Oficina de Robótica** aparece na Área de Trabalho.
- [ ] A configuração contém códigos válidos de região, atividade e perguntas.
- [ ] Sede, regional e escola aparecem corretamente no perfil da instalação.
- [ ] O fluxo de assentimento e o protocolo de ajuda foram explicados ao instrutor.
- [ ] Foi realizado um teste com internet e outro sem internet.
- [ ] O evento apareceu em `research_events` após a sincronização.
- [ ] A sessão produziu `session_started`, `heartbeat` e `session_completed` em `research_session_events`.
- [ ] A sessão recebeu o estado esperado em `research_session_quality`.

## Solução de problemas

### O instalador pede credenciais

O `.env` não foi encontrado ou está com nomes incorretos. Verifique se contém exatamente `PULSELAB_URL` e `PULSELAB_KEY`.

### O agente informa que faltam credenciais

Execute o instalador novamente no mesmo usuário que abrirá o atalho. As variáveis são gravadas no escopo do usuário do Windows; outro usuário da máquina não as herdará.

### A oficina não aparece no Supabase

Verifique `%LOCALAPPDATA%\PulseLab\pulselab.log`, a conectividade HTTPS e o conteúdo de `%LOCALAPPDATA%\PulseLab\cache\research-queue.json`.

### O screenshot não aparece

Screenshots dependem de o aplicativo SPIKE estar aberto e de o bucket privado permitir upload. As imagens privadas devem ser acessadas por backend autorizado, não por link público.

### O agente usa configuração antiga

Verifique `config_remote_url`, a versão registrada no log e se a máquina consegue acessar o conteúdo raw do GitHub. Em modo offline, o último arquivo local válido é usado.

---

## Testar o agente no Windows com checkpoints acelerados

Estas instruções percorrem o agente real em WPF. Use somente códigos e dados de
teste.

### 1. Baixar a versão correta

Em uma pasta de trabalho, abra o PowerShell:

```powershell
git clone https://github.com/vfamim/pulselab.git
cd pulselab
git switch main
```

Se o repositório já estiver no computador:

```powershell
git fetch origin
git switch main
git pull --ff-only
```


Confirme que o agente é a versão 1.5.0:

```powershell
Select-String .\agent\pulselab-agent.ps1 -Pattern 'Version    :'
```

### 2. Escolher o modo de teste

Para testar o fluxo completo com a configuração remota e o Supabase, execute:

```powershell
.\Testar-Pulselab-Rapido.bat
```

Nesse modo, os marcos continuam identificados como 20 e 40 minutos no banco,
mas as janelas aparecem aproximadamente aos 20 e 40 segundos.

Para abrir os checkpoints consecutivamente, sem editar `config.json` nem
desligar o Wi-Fi, execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\pulselab.ps1 -DebugMode
```

`-DebugMode` usa o arquivo local, mantém os identificadores 20 e 40 e elimina a
espera somente para essa execução. Nenhum valor precisa ser restaurado depois.
O agente exige uma sessão de dispositivo válida protegida por DPAPI, além da URL e da chave pública `anon`.

## Verificações automatizadas

Execute os testes de contrato com Python 3:

```bash
python3 -m unittest discover -s tests -v
```

Os testes conferem configuração, versões, eventos aceitos pelo schema, permissões do coletor, minimização da telemetria, integridade básica dos blocos XAML e conteúdo embutido no instalador.

Para verificar também o simulador web:

```bash
npm test --prefix web/agent-simulator
npm run check --prefix web/agent-simulator
npm run build --prefix web/agent-simulator
```
