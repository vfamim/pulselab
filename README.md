# PulseLab

Camada de observabilidade pedagógica para oficinas do projeto Robótica Educativa (UNIVASF).
A tela das crianças roda no navegador em modo silencioso; um servidor local em PowerShell
(porta 43128) guarda os registros no próprio computador, analisa passivamente contagens
estruturais de blocos dos projetos LEGO SPIKE Prime e exporta dados para pendrive ou nuvem.

## Estado (v2.3.2)

- **Experiência Silenciosa do Aluno**: Durante a oficina, a tela exibida para os estudantes
  é 100% silenciosa e sem atrito pedagógico. Não há questionários, formulários, escalas
  Likert nem popups intrusivos durante a atividade. A interface exibe apenas uma orientação
  neutra para uso do software oficial LEGO SPIKE Prime.
- **Bancada Coletiva como Unidade de Análise (LGPD Art. 14)**: A unidade de observação é
  a bancada coletiva (2 a 8 integrantes, `group_size`). Em estrita conformidade com a
  proteção de crianças e adolescentes, **não são coletados** nomes, fotos, vídeos, áudios,
  e-mails, matrículas, digitação de teclado (`GetAsyncKeyState`) nem capturas de tela (screenshots).
- **Coleta Passiva de Telemetria SPIKE**: O Bridge local inspeciona periodicamente os
  projetos salvos do LEGO SPIKE Prime (`.llsp3`, Scratch `.sb3`, Python) a cada 10 segundos
  via `/v1/spike/metrics`. São extraídas apenas métricas agregadas estruturais (blocos
  executáveis, pilhas, uso de motor, sensor, loop e condicional), sem armazenar código bruto,
  variáveis ou identificadores do Hub.
- **Encerramento de Turma pelo Educador/Bancada**: A sessão da turma vai da abertura do app
  (ou fim da turma anterior) até o acionamento do botão discreto **Encerrar turma**. No encerramento,
  a bancada responde a uma pergunta rápida com 4 carinhas sobre a oficina e o educador
  registra o resultado (0 a 3) e o apoio recebido (nenhum, algum, muito). Os itens estão
  em `web/agent-simulator/lib/contracts.js` como rascunho até validação do pesquisador.
- **Modo Laboratório (`?lab=1`)**: Parâmetro de URL reservado para desenvolvimento,
  homologação e testes de engenharia. Permite inspecionar o outbox local, verificar a saúde
  do Bridge, simular telemetria sintética e acionar expurgo de dados sem poluir a tela normal.
- **Coleta Desativada por Padrão (Modo Livre)**: O pacote genérico opera em Modo Livre
  (zero gravação, zero envio). A coleta de pesquisa só é ativada pelo pacote do polo, que
  traz `provisionamento.json` com a sede, token de cadastro e o CAAE do parecer ético do CEP.
- **Persistência em Dupla Camada**: Os dados são registrados concomitantemente no IndexedDB
  do navegador (`pulselab-student-runner`) e em arquivos locais do Bridge (`dados_locais/events.jsonl`
  e `dados_locais/sessions.jsonl`), garantindo integridade mesmo perante reinicializações ou quedas.
- **Retenção Local Configurável**: Os registros ficam no computador por `retention_days` do
  pacote do polo (padrão 180 dias, ajustável de 1 a 365 dias), mesmo após exportação ou envio.
  O botão "Parar de participar e apagar meus dados" executa expurgo local e remoto definitivo imediato.
- Escola, oficina e turma não informadas ficam como `nao_informado`, nunca com valores genéricos.
- Os itens, rubricas e a pergunta de pesquisa ainda dependem de validação acadêmica.
  Veja [protocolo v2](docs/protocolo-pesquisa-v2-teste.md) e
  [plano de validação](docs/plano-validacao-v2.md).

## Para os polos

1. Baixe o pacote do seu polo e extraia o ZIP.
2. Rode `Instalar-PulseLab.bat` e, se quiser, informe o nome da máquina (ex.: `PET-LAB1-PC03`).
3. Use os atalhos **PulseLab - Iniciar Oficina** e **PulseLab - Exportar Dados**.

Reinstalar com um pacote de polo mais novo mantém a identificação da máquina e os registros.

## Envio para a nuvem

Cada computador guarda tudo localmente e envia ao Supabase quando tiver internet, a cada
30 segundos. Máquinas offline (ex.: Senhor do Bonfim) enviam quando o instrutor conectar.

1. O coordenador gera um token do polo, válido para várias máquinas:
   `python3 supabase/scripts/provision_device.py --site-id PET --token-polo --max-usos 40 --validade-dias 60 --output token-PET.json`
   (precisa da service role; o arquivo de saída fica com permissão 0600 e não vai para o repositório).
2. O token entra no pacote do polo:
   `python3 scripts/gerar-pacote-polo.py --polo PET --regional Petrolina --caae <CAAE> --token-cadastro token-PET.json`
3. No primeiro contato com a internet, cada máquina se cadastra sozinha, apaga o token do disco
   e passa a renovar o acesso (validade de 1 hora) por conta própria.

O token vai dentro do ZIP do polo. Se o pacote circular fora do polo, revogue o token
(`revoked_at` em `device_enrollment_tokens`) e gere outro pacote. O snapshot da sessão sobe uma
vez, quando a turma é encerrada (ou abandonada há mais de 12 horas); os eventos sobem um a um.

Antes do primeiro uso, aplique no Supabase a migração `20261011150000_site_enrollment_tokens.sql`
e publique a função `enroll-device`.

## Identificação da máquina

`dados_locais/installation.json` guarda um `installation_id` aleatório, o rótulo escolhido
na instalação e os dados do polo. A pasta `dados_locais` nunca é sobrescrita por
atualização ou reinstalação. Exportações usam o rótulo, nunca o nome do Windows ou do usuário.

## Atualização automática

Ao abrir, o launcher consulta a última release publicada no GitHub (até 2 s sem internet).

- O manifesto `pulselab-update.json` precisa estar assinado pela chave do projeto.
  A chave pública vai no pacote (`release-public-key.json`). Sem ela, não há atualização.
- O ZIP é conferido pelo SHA-256 do manifesto assinado e instalado com troca de pastas.
  A versão anterior fica em `_update_backup`.
- Se o servidor local não subir depois da troca, a versão anterior volta e a nova fica bloqueada
  naquela máquina.
- Com o servidor já em execução, a atualização fica para a próxima abertura.

## Publicar uma versão

```sh
python3 scripts/publicar-release.py gerar-chave       # uma vez; chave privada em ~/.pulselab
./scripts/build-offline-package.sh                    # gera o ZIP da versão em VERSION
python3 scripts/publicar-release.py publicar --pre    # pré-release: não chega às máquinas
gh release edit vX.Y.Z --prerelease=false --latest    # promove: máquinas atualizam
```

Pacote de polo:

```sh
python3 scripts/gerar-pacote-polo.py --polo PET --regional Petrolina --caae 12345678.9.0000.1234 --retencao-dias 180
python3 scripts/gerar-pacote-polo.py --polo SBF --regional "Senhor do Bonfim" --sem-pesquisa
```

## Desenvolvimento

```sh
cd web/agent-simulator && npm ci && npm run test:unit && npm run build
python3 scripts/check-version-consistency.py
python3 -m unittest scripts.test_importador scripts.test_council scripts.test_release scripts.test_build_hosting scripts.test_bridge_cloud
pwsh -File scripts/test-launcher-update.ps1
python3 scripts/check-database.py   # Docker: migrações e RLS num Postgres descartável
```

O site no Firebase publica apenas a lista de pastas de `scripts/build-hosting.py`
(montada em `hosting-dist/`). Toda mudança passa por PR com o CI verde.

Documentos v1/v1.4, o agente WPF (`agent/`) e o portal antigo são referências históricas.
