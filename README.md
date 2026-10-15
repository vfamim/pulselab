# PulseLab

Camada de observação das oficinas do projeto Robótica Educativa (UNIVASF). O PulseLab
inicia com o Windows e fica como um ícone na área de notificação (bandeja); nenhuma página
fica aberta durante a aula. Um servidor local em PowerShell (porta 43128) guarda os
registros no próprio computador, lê a estrutura dos projetos LEGO SPIKE e exporta para
pendrive.

## Estado

- A coleta de pesquisa vem **desligada** no pacote genérico. Ela só liga com o pacote
  do polo, que traz `provisionamento.json` com a sede e o CAAE do parecer ético.
- A unidade de análise é a bancada. Não há nomes, fotos, câmera, captura de tela nem teclado.
- Assentimento verbal: no início de cada aula o instrutor lê um roteiro padronizado às crianças.
  Não há caixas de assentimento nem botão de retirada na tela. Se alguém recusar, o instrutor
  escolhe **Não registrar esta turma** no menu da bandeja daquele computador: os dados da turma
  atual são apagados (com marca de exclusão) e o registro pausa até a próxima turma. Depende de
  emenda ao CEP. Veja [assentimento verbal](docs/assentimento-verbal.md).
- A sessão começa quando o PulseLab inicia (ou, depois de uma turma encerrada, no primeiro programa
  salvo) e termina por **Encerrar turma…** no menu da bandeja
  (pergunta coletiva com 4 carinhas ou "Preferimos não responder"; resultado 0 a 3 e apoio
  nenhum/algum/muito, que o instrutor pode pular). Sem encerramento, fecha sozinha depois de
  3 horas ou de mais de 20 minutos com o computador desligado. Os itens estão em
  `web/agent-simulator/lib/contracts.js` como rascunho até validação do pesquisador.
- Cada sessão registra como terminou (instrutor, tempo, sem encerramento), interrupções e a
  situação da pasta do SPIKE. Do programa: estrutura de cada versão salva (só tipos de blocos),
  escore de pensamento computacional adaptado de Dr. Scratch (não validado) e, com calendário de
  missões, a cobertura da missão.
- Escola, oficina e turma não informadas ficam como `nao_informado`, nunca com valores genéricos.
- Os registros ficam no computador por `retention_days` do pacote do polo (padrão 180 dias),
  mesmo depois de exportados ou enviados. O prazo precisa constar no protocolo e no TCLE.
- Os itens, rubricas e a pergunta de pesquisa ainda dependem de validação acadêmica.
  Veja [protocolo v2](docs/protocolo-pesquisa-v2-teste.md),
  [plano de validação](docs/plano-validacao-v2.md) e [roadmap](docs/roadmap.md).

## Para os polos

1. Baixe o pacote do seu polo e extraia o ZIP.
2. Rode `Instalar-PulseLab.bat` e, se quiser, informe o nome da máquina (ex.: `PET-LAB1-PC03`).
3. O PulseLab abre com o Windows. Use o menu do ícone na bandeja durante a aula e o atalho
   **PulseLab - Exportar Dados** para copiar os registros para pendrive.

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
vez, quando a sessão é encerrada (pelo instrutor ou automaticamente); os eventos sobem um a um.
O painel mostra as máquinas que estão sem enviar dados há alguns dias.

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
python3 -m unittest scripts.test_importador scripts.test_release scripts.test_build_hosting scripts.test_bridge_cloud scripts.test_spike_parser
pwsh -File scripts/test-launcher-update.ps1
python3 scripts/check-database.py   # Docker: migrações e RLS num Postgres descartável
```

O site no Firebase publica apenas a lista de pastas de `scripts/build-hosting.py`
(montada em `hosting-dist/`). Toda mudança passa por PR com o CI verde.

Documentos v1/v1.4, o agente WPF (`agent/`) e o portal antigo são referências históricas.
