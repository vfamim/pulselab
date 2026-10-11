# Roteiro de Testes e Homologação Operacional — PulseLab v2.3.3

Este roteiro orienta o procedimento de validação funcional e auditoria ética dos recursos
operacionais do PulseLab na versão 2.3.3.

---

## 1. Inicialização do Ambiente

### 1.1 Ambiente Windows (Ambiente Escolar / Teste Portátil)
1. Extraia o pacote `PulseLab-2.3.2-Windows.zip` em uma pasta local.
2. Execute `Iniciar-PulseLab.bat` (modo portátil) ou utilize o atalho **"PulseLab - Iniciar Oficina"** criado por `Instalar-PulseLab.bat`.
3. O servidor Bridge sobe automaticamente em loopback na porta `43128` e abre o navegador em:
   ```text
   http://127.0.0.1:43128/alunos/
   ```
4. Para inspeção de engenharia e diagnósticos sintéticos, acesse com o parâmetro:
   ```text
   http://127.0.0.1:43128/alunos/?lab=1
   ```

### 1.2 Ambiente Linux / macOS (Desenvolvimento Web)
1. No diretório `web/agent-simulator/`, execute:
   ```bash
   npm ci
   npm run dev -- --host 127.0.0.1 --port 4179
   ```
2. Acesse `http://127.0.0.1:4179/alunos/` (ou `http://127.0.0.1:4179/alunos/?lab=1`).

---

## 2. Matriz de Cenários de Aceitação

| Cenário | Procedimento de Teste | Resultado Esperado |
|---|---|---|
| **1. Experiência Silenciosa do Aluno** | Abrir a rota `/alunos/` sem parâmetros adicionais durante a oficina. | A interface exibe unicamente a mensagem neutra: *"Oficina de robótica em andamento. Use o aplicativo LEGO SPIKE"*. Zero formulários, questionários ou popups na tela. |
| **2. Modo Livre por Padrão** | Executar a aplicação sem o arquivo `provisionamento.json` configurado. | A aplicação entra em Modo Livre fail-closed: nenhuma informação é gravada no IndexedDB ou Bridge, e nenhum envio para a nuvem é realizado. |
| **3. Ativação por Pacote do Polo** | Inserir `provisionamento.json` válido (com CAAE e `research_collection_enabled: true`). | O sistema inicializa a sessão coletiva da bancada (`group_size` entre 2 e 8) em segundo plano, habilitando a persistência dupla. |
| **4. Coleta Passiva de Telemetria SPIKE** | Salvar um projeto no LEGO SPIKE Prime (`.llsp3`, Scratch `.sb3` ou Python). | A cada 10s, o Bridge detecta o arquivo alterado e emite evento `spike_telemetry` com métricas estruturais (blocos executáveis, motores, sensores, loops). Nenhuma janela ou alerta interrompe os estudantes. |
| **5. Encerramento de Turma** | Ao fim da aula, clicar no botão discreto **"Encerrar turma"** no canto inferior. | 1. Modal pergunta: *"Como foi a oficina para a sua bancada hoje?"* (4 carinhas ou *"Preferimos não responder"*).<br>2. Educador preenche resultado da bancada (0 a 3) e nível de apoio (nenhum, algum, muito).<br>3. Sessão é finalizada e o app reseta para a próxima turma. |
| **6. Modo Laboratório (`?lab=1`)** | Acessar `/alunos/?lab=1`. | Exibe painel lateral de diagnóstico técnico: status do Bridge, métricas da telemetria SPIKE ao vivo, botões para simulação de eventos e gatilho de retirada ética. |
| **7. Persistência em Dupla Camada** | Realizar uma oficina com telemetria e inspecionar os armazenamentos locais. | Os eventos são persistidos simultaneamente no IndexedDB (`pulselab-student-runner`) e nos arquivos `.jsonl` em `dados_locais/` (`events.jsonl`, `sessions.jsonl`). |
| **8. Sincronização em Nuvem (Supabase)** | Conectar a máquina à internet com token de polo cadastrado. | O motor Store-and-Forward envia lotes de eventos pendentes a cada 30 segundos, marcando-os como entregues após confirmação do servidor. |
| **9. Exportação Offline (Pendrive)** | Executar o atalho **"PulseLab - Exportar Dados"** ou script `exportar-dados.ps1`. | Gera arquivo ZIP em pendrive ou na pasta escolhida, contendo os arquivos `.jsonl` e o manifesto de integridade com checksum SHA-256. |
| **10. Retirada Ética e Expurgo** | Acionar o botão *"Parar de participar e apagar meus dados"*. | Exclui atomicamente todos os dados locais do IndexedDB e do Bridge, grava um tombstone durável contra ressincronização e agenda exclusão remota. |
| **11. Atualização Automática Assinada** | Iniciar o launcher `pulselab.ps1` com nova versão publicada no GitHub. | Launcher valida a assinatura RSA-SHA256 em `pulselab-update.json` contra `release-public-key.json` e o hash do ZIP. Em caso de falha de inicialização, executa rollback para `_update_backup`. |

---

## 3. Verificações de Isolamento e Conformidade Ética (LGPD Art. 14)

1. **Minimização Absoluta**:
   - Abrir o console de desenvolvedor (F12) e inspecionar as requisições de rede.
   - Confirmar que nenhum nome de estudante, foto, vídeo, áudio, IP externo ou digitação de teclado é transmitido ou gravado.
2. **Proteção de Pastas do Usuário**:
   - Confirmar que nenhuma pasta é criada em `%LOCALAPPDATA%` ou `%APPDATA%`. Todos os dados da instalação permanecem na pasta portátil `dados_locais/`.
3. **Respeito ao Prazo de Retenção**:
   - Confirmar que o prazo `retention_days` do polo (padrão de 180 dias) é respeitado pelas rotinas de expurgo do navegador e do Bridge.
