# PulseLab

Camada de observação das oficinas do projeto Robótica Educativa (UNIVASF). A tela das
crianças roda no Microsoft Edge; um servidor local em PowerShell (porta 43128) guarda
os registros no próprio computador, lê contagens de blocos dos projetos LEGO SPIKE e
exporta para pendrive.

## Estado

- A coleta de pesquisa vem **desligada** no pacote genérico. Ela só liga com o pacote
  do polo, que traz `provisionamento.json` com a sede e o CAAE do parecer ético.
- A unidade de análise é a bancada. Não há nomes, fotos, câmera, captura de tela nem teclado.
- A sessão de uma turma vai da abertura do app (ou do fim da turma anterior) até o toque em
  **Encerrar turma**. No encerramento, a bancada responde uma pergunta com 4 carinhas e o
  instrutor registra resultado (0 a 3) e apoio (nenhum, algum, muito). Os itens estão em
  `web/agent-simulator/lib/contracts.js` como rascunho até validação do pesquisador.
- Escola, oficina e turma não informadas ficam como `nao_informado`, nunca com valores genéricos.
- Os registros ficam no computador por `retention_days` do pacote do polo (padrão 180 dias),
  mesmo depois de exportados ou enviados. O prazo precisa constar no protocolo e no TCLE.
- Os itens, rubricas e a pergunta de pesquisa ainda dependem de validação acadêmica.
  Veja [protocolo v2](docs/protocolo-pesquisa-v2-teste.md) e
  [plano de validação](docs/plano-validacao-v2.md).

## Para os polos

1. Baixe o pacote do seu polo e extraia o ZIP.
2. Rode `Instalar-PulseLab.bat` e, se quiser, informe o nome da máquina (ex.: `PET-LAB1-PC03`).
3. Use os atalhos **PulseLab - Iniciar Oficina** e **PulseLab - Exportar Dados**.

Reinstalar com um pacote de polo mais novo mantém a identificação da máquina e os registros.

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
python3 -m unittest scripts.test_importador scripts.test_council scripts.test_release scripts.test_build_hosting
pwsh -File scripts/test-launcher-update.ps1
```

O site no Firebase publica apenas a lista de pastas de `scripts/build-hosting.py`
(montada em `hosting-dist/`). Toda mudança passa por PR com o CI verde.

Documentos v1/v1.4, o agente WPF (`agent/`) e o portal antigo são referências históricas.
