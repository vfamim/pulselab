---
marp: true
lang: pt-BR
title: PulseLab — Guia do instrutor
description: Como instalar e usar o PulseLab nas oficinas de robótica.
paginate: true
size: 16:9
style: |
  section {
    font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif;
    background: #f8fafc;
    color: #1e293b;
    padding: 40px 56px;
    font-size: 24px;
    line-height: 1.45;
  }
  h1 { color: #1d4ed8; font-size: 1.6em; margin: 0 0 0.4em; }
  h2 { color: #0f172a; font-size: 1.05em; margin: 0.6em 0 0.2em; }
  strong { color: #0f172a; }
  code { background: #e2e8f0; color: #0f172a; border-radius: 4px; padding: 0 6px; font-size: 0.9em; }
  ol, ul { margin: 0.2em 0; }
  li { margin: 0.15em 0; }
  section.capa { justify-content: center; }
  section.capa h1 { font-size: 2.2em; }
  .tag { display: inline-block; background: #dbeafe; color: #1e40af; border-radius: 999px; padding: 2px 14px; font-size: 0.75em; font-weight: 600; }
  .cols { display: grid; grid-template-columns: 1fr 1fr; gap: 32px; }
  .caixa { background: #ffffff; border: 1px solid #cbd5e1; border-radius: 10px; padding: 12px 18px; }
  .alerta { background: #fef3c7; border: 1px solid #f59e0b; border-radius: 10px; padding: 10px 18px; }
  .dot { display: inline-block; width: 0.8em; height: 0.8em; border-radius: 50%; vertical-align: -0.05em; margin-right: 8px; }
  .verde { background: #16a34a; } .amarelo { background: #eab308; } .vermelho { background: #dc2626; }
  table { font-size: 0.85em; border-collapse: collapse; }
  th, td { padding: 6px 12px; border-bottom: 1px solid #cbd5e1; text-align: left; vertical-align: top; }
  footer { color: #64748b; font-size: 0.6em; }
footer: PulseLab 3 · Guia do instrutor
---

<!-- _class: capa -->
<!-- _paginate: false -->

<span class="tag">PulseLab 3</span>

# Guia do instrutor

O PulseLab registra, para cada bancada, como o programa do robô LEGO SPIKE muda durante a aula.

Ele **não** guarda nomes, não tira fotos, não filma, não grava voz e não registra o que se digita ou clica. Durante a aula, aparece só como um ícone perto do relógio do Windows.

---

# Antes de tudo: o pacote certo

<div class="cols">
<div class="caixa">

## Pacote do seu polo

Entregue pela coordenação. Liga o registro de pesquisa.

Na instalação aparece:
`Coleta de pesquisa ATIVA - polo ...`

</div>
<div class="caixa">

## Pacote genérico do site

`PulseLab-<versão>-Windows.zip`. Funciona, mas **não registra nada** (Modo Livre).

Na instalação aparece:
`Coleta de pesquisa DESLIGADA neste computador`

</div>
</div>

Use sempre o pacote do polo nos computadores das oficinas.

---

# Instalação (uma vez por computador)

1. Copie o ZIP para o computador. Não precisa de internet nem de senha de administrador.
2. Clique com o botão direito no ZIP e escolha **Extrair tudo...**
3. Na pasta extraída, dê dois cliques em **`Instalar-PulseLab.bat`**.
4. Digite o nome da máquina, por exemplo `PET-LAB1-PC03`, e aperte Enter. Esse nome identifica a bancada nos dados.
5. Espere a mensagem **`Instalacao concluida com sucesso!`**

Ficam dois atalhos na Área de Trabalho, **PulseLab - Iniciar Oficina** e **PulseLab - Exportar Dados**, e o PulseLab passa a abrir sozinho com o Windows.

<div class="alerta">Se aparecer "O instalador foi aberto sem extrair o arquivo ZIP", feche a janela e volte ao passo 2.</div>

---

# Um computador, uma bancada

- Cada computador corresponde a **uma bancada** (2 a 8 crianças). O registro é da bancada, nunca de uma criança.
- As crianças salvam o projeto no **aplicativo LEGO SPIKE desse mesmo computador**, na pasta padrão `Documentos\LEGO SPIKE`.
- O PulseLab olha essa pasta a cada 15 segundos e guarda só a estrutura do programa: quantos blocos, motores, sensores, repetições e condições.
- Nenhuma tela do PulseLab aparece para as crianças.

---

# Início da aula

1. Ligue os computadores. O PulseLab abre sozinho; confira o ícone perto do relógio.
2. Leia para a turma o **roteiro de assentimento verbal** entregue pela coordenação e responda às dúvidas.
3. Comece a oficina normalmente.

O registro da turma começa sozinho, no primeiro programa salvo no LEGO SPIKE.

Se o ícone não aparecer, use o atalho **PulseLab - Iniciar Oficina**.

---

# O ícone perto do relógio

| Cor | O que significa | O que fazer |
|---|---|---|
| <span class="dot verde"></span>Verde | Ligado e registrando, ou pronto para a próxima turma | Nada |
| <span class="dot amarelo"></span>Amarelo | Ligado, mas sem registrar: Modo Livre (pacote genérico), turma marcada como "não registrar", ou pasta do LEGO SPIKE não encontrada | Clique com o botão direito e veja **Ver situação** |
| <span class="dot vermelho"></span>Vermelho | O PulseLab parou de responder | Espere 1 minuto: ele religa sozinho |

Passe o mouse sobre o ícone para ler a situação, por exemplo `PulseLab - registrando a turma desde 14:05`.

---

# O menu do ícone (botão direito)

| Item | O que faz |
|---|---|
| **Encerrar turma...** | Pergunta se quer encerrar. Em **Sim**, finaliza a gravação desta aula. Não há formulário nem perguntas. |
| **Não registrar esta turma** | Apaga os dados desta turma neste computador e pausa o registro até a próxima aula. A bancada continua usando tudo normalmente. |
| **Ver situação** | Mostra o nome do computador, se a turma está sendo registrada, quantos programas SPIKE foram vistos e se há dados esperando envio. |
| **Fechar PulseLab** | Desliga o PulseLab até o próximo início do Windows. Use só quando pedirem. |

---

# Se alguém não quiser participar

<div class="cols">
<div>

## Faça

1. Agradeça e **não pergunte o motivo**.
2. No computador daquela bancada: botão direito no ícone, **Não registrar esta turma**, **Sim**.
3. Siga a aula normalmente. A bancada continua montando e programando.

</div>
<div>

## Nunca

- Expor ou chamar a criança pelo nome
- Insistir, negociar ou oferecer prêmio
- Separar a criança da bancada
- Fazer a bancada "votar"

</div>
</div>

Recusa avisada depois da aula: informe à equipe de pesquisa o nome do computador, a data e o horário. Se o roteiro não foi lido, use **Não registrar esta turma** em todos os computadores da turma.

---

# Fim da aula

1. Botão direito no ícone, **Encerrar turma...**, **Sim**.
2. Aparece **Turma encerrada com sucesso. Pronto para a próxima aula.**

O PulseLab **continua ligado**. A próxima turma começa sozinha no primeiro programa salvo no LEGO SPIKE.

Esqueceu de encerrar? A turma é encerrada sozinha depois de **3 horas**, ou quando o computador fica **20 minutos ou mais desligado ou suspenso**.

---

# Onde ficam os dados

- No próprio computador, na pasta `%LOCALAPPDATA%\PulseLab\dados_locais`, pelo prazo definido pelo polo (padrão: 180 dias). Atualizações e reinstalações não apagam essa pasta.
- Com internet e computador cadastrado, os dados vão para a nuvem sozinhos. **Ver situação** mostra `Envio para a nuvem: ativo`.
- Sem internet (`Envio para a nuvem: não configurado (use o pendrive)`):
  1. Coloque um pendrive e abra o atalho **PulseLab - Exportar Dados**.
  2. Espere **EXPORTACAO CONCLUIDA COM SUCESSO!**
  3. Entregue o pendrive à coordenação. Os arquivos ficam na pasta `Coleta-PulseLab`.

---

# Atualizações

- Acontecem sozinhas quando o computador liga com internet. Não aparece nada na tela e não há nada a fazer.
- Só são aceitas atualizações assinadas pelo projeto.
- Se a versão nova não funcionar, o PulseLab volta sozinho para a anterior.
- Os dados das turmas nunca são apagados por uma atualização.

---

# Quando algo dá errado

| Situação | O que fazer |
|---|---|
| Ícone vermelho por mais de 2 minutos | Abra o atalho **PulseLab - Iniciar Oficina**. Se continuar, reinicie o computador. |
| Amarelo e **Ver situação** diz "Registro de pesquisa: desligado" | O pacote instalado é o genérico. Reinstale com o pacote do polo. |
| Amarelo e aviso de pasta do LEGO SPIKE não encontrada | Salve um projeto no aplicativo LEGO SPIKE desse computador. |
| Nenhum ícone perto do relógio | Abra o atalho **PulseLab - Iniciar Oficina**. Confira também os ícones ocultos (seta ^ ao lado do relógio). |
| Erro ao instalar: "Nao foi possivel copiar os arquivos" | Feche o PulseLab (botão direito no ícone, **Fechar PulseLab**) e rode o instalador de novo. |

Persistindo, avise a coordenação com o nome do computador e uma foto da mensagem, **sem crianças na imagem**.

---

# Para a coordenação

- **Remover o PulseLab:** primeiro exporte os dados. Depois, **Fechar PulseLab**, apague os atalhos da Área de Trabalho, o atalho `PulseLab` da pasta Inicializar do Windows e a pasta `%LOCALAPPDATA%\PulseLab`. Apagar essa pasta apaga os dados do computador.
- **Diagnóstico:** `http://127.0.0.1:43128/health` deve responder `ok`. O registro técnico fica em `dados_locais\bridge.log`.
- **Roteiro de assentimento e regras de recusa:** `docs/campo/assentimento-verbal.md` no repositório do projeto.

---

<!-- _class: capa -->

# Resumo

| Momento | Ação |
|---|---|
| Início | Confira o ícone e leia o roteiro de assentimento |
| Durante | Nada. As crianças salvam os projetos no LEGO SPIKE |
| Recusa | **Não registrar esta turma** no computador da bancada |
| Fim | **Encerrar turma...** e **Sim** |
| Sem internet | **PulseLab - Exportar Dados** com pendrive |
