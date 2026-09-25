# PulseLab — teste do protocolo v2

Esta branch é uma versão isolada para testar as mudanças da revisão adversarial.
Use somente dados fictícios. Não está liberada para pesquisa com crianças.

## Experimentar

No Windows, baixe [PulseLab-TESTE-v2-Windows.zip](test-packages/PulseLab-TESTE-v2-Windows.zip)
nesta branch (botão de download do arquivo), extraia todo o ZIP e execute
**Iniciar-PulseLab.bat**. A página abre em
http://127.0.0.1:43128/alunos/. A janela do servidor deve permanecer aberta.

No desenvolvimento:

```sh
cd web/agent-simulator
npm ci
npm run dev -- --host 127.0.0.1 --port 4179
```

Abra http://127.0.0.1:4179/alunos/. Veja o [roteiro de teste](docs/roteiro-teste-v2.md).

O teste usa banco local próprio, porta distinta da instalação principal,
sem chaves de produção, envio à nuvem, atualização automática ou leitura de pastas.
A PWA armazena registros no navegador por sete dias desde o início da sessão.
A limpeza ocorre ao abrir o app e durante sessões ativas. Exportações ficam sob
responsabilidade de quem as baixou. O pacote é portátil, sem instalação.

## O que mudou

- Assentimento separado de cada integrante, inicialmente desmarcado.
- Recusa inicia atividade livre, sem sessão, respostas, eventos ou telemetria.
- Retirada apaga todos os registros locais da sessão.
- Bancada como unidade de análise, com identidade estável e tamanho real do grupo.
- Instrumento único versionado, incluído na exportação com seu hash SHA-256.
- Itens de esforço, confiança, participação e intenção com dimensões separadas;
  recusa por item e ausência de consenso são preservadas.
- Contexto institucional obrigatório por códigos; papéis confirmados manualmente.
- Checkpoints com horários reais e indicação de antecipação/atraso.
- Ajuda com pedido, reconhecimento, início e resolução.
- Rubrica separa três tentativas de execução, explicação e quantidade de apoio.
- Devolutiva registra a próxima ação pedagógica.
- Artefato selecionado manualmente; apenas contagens e categorias de blocos.
  Não há classificação automática de missão nem probabilidade de aprendizagem.
- Completude operacional, cobertura de respostas e disponibilidade de resultado
  aparecem separadamente.
- Migração preparada para revogar acesso anônimo, restringir leitura por sede e
  permitir descarte somente mediante política institucional explícita.

## Pesquisa e limites

A pergunta do piloto é a viabilidade e validade de uma coleta mínima em oficinas,
não o efeito causal da robótica. Os itens, rubricas e adaptações por faixa escolar
ainda precisam de validação humana. Não há resultados empíricos de aprendizagem
ou equidade produzidos por esta branch.

- [Protocolo v2 e decisões pendentes](docs/protocolo-pesquisa-v2-teste.md)
- [Inventário de dados e limitações](docs/inventario-dados-v2.md)
- [Plano de validação acadêmica e social](docs/plano-validacao-v2.md)
- [Matriz de resposta à revisão](docs/matriz-revisao-v2.md)

Documentos v1/v1.4, o agente WPF e o portal antigo são referências históricas:
não descrevem o executável deste pacote. A avaliação do instrutor está integrada
ao novo fluxo local. O backend remoto não recebe os novos exports v2.

## Verificação e pacote

```sh
cd web/agent-simulator
npm run check
cd ../..
python3 scripts/check-database.py
./scripts/build-offline-package.sh
```

Os testes de banco criam um container descartável próprio com dados sintéticos.
Nenhuma migração é aplicada a Supabase remoto. O pacote e seu SHA-256 estão
versionados na branch. A credencial disponível não permite alterar workflows;
a automação proposta está em `docs/ci/research-v2-test.workflow.yml`, ainda
inativa. O build bloqueia publicação pelo workflow live da main.

Os testes foram executados localmente. O servidor tem smoke test executável
com `powershell -File scripts/test-portable-server.ps1` no Windows; o teste
manual do inicializador no seu Windows continua parte deste PR experimental.
