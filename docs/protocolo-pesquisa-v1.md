# Protocolo de Pesquisa PulseLab v1

> Status: versão de trabalho para revisão pedagógica, ética e estatística.
> Compatibilidade técnica: agente e schema 1.4.0.
> População: estudantes participantes de oficinas pontuais de robótica educacional com LEGO SPIKE, com idade máxima prevista de 15 anos. A idade mínima ainda precisa ser definida para adequar linguagem, assentimento e instrumentos.

## 1. Enquadramento

O projeto recebe turmas distintas em escolas e regiões diferentes. Por isso, o desenho proposto é um **estudo observacional multicêntrico, de cortes transversais repetidos, com medidas intrassessão**.

Cada estudante participa de uma única oficina, mas pode responder em mais de um momento dentro dela. O protocolo permite analisar processos e resultados imediatos. Não permite, sem seguimento adicional, medir desenvolvimento individual ou retenção de longo prazo.

As oficinas consistem na montagem e programação, no aplicativo LEGO SPIKE, de um robô autônomo. O encerramento costuma incluir uma dinâmica com quiz controlado pelo robô e uma corrida entre equipes. Essas atividades serão registradas como evidências de desempenho e engajamento, mas não serão tratadas isoladamente como prova de aprendizagem.

## 2. Objetivo geral

Analisar as relações entre esforço mental percebido, colaboração em dupla, necessidade de ajuda e desempenho imediato de estudantes durante oficinas pontuais de robótica educacional com LEGO SPIKE.

## 3. Objetivos específicos

1. Descrever o esforço mental percebido aos 20 e 40 minutos.
2. Identificar episódios de bloqueio e necessidade de mediação.
3. Comparar as percepções dos papéis de programação e montagem.
4. Examinar a relação entre colaboração, intervenção do instrutor e desempenho da missão.
5. Estimar o ganho imediato em conhecimentos específicos quando existirem itens pré e pós equivalentes.
6. Avaliar a viabilidade operacional da coleta distribuída em diferentes escolas.

As oficinas são normalmente realizadas em duplas. Em situações especiais, podem participar três crianças por grupo, especialmente quando há redução de instrutores ou composição excepcional da turma. O protocolo principal continua sendo o de duplas; grupos de três exigirão um papel adicional e análise separada.

## 4. Hipóteses iniciais

- H1: o esforço mental percebido apresenta diferença entre os minutos 20 e 40.
- H2: o relato de bloqueio está associado a maior frequência de intervenção do instrutor.
- H3: participação mais equilibrada está associada a melhor desempenho na missão final.
- H4: o desempenho nos itens de conhecimento é superior após a oficina.

H4 somente poderá ser testada depois que os objetivos pedagógicos e os itens específicos de cada atividade forem definidos.

## 5. Fluxo de coleta

### 5.1 Antes de iniciar

O instrutor informa:

- código da escola;
- código da oficina;
- código da turma;
- confirmação de que as autorizações e o consentimento aplicáveis foram verificados.

Os códigos operacionais são reapresentados com os últimos valores salvos na máquina. O instrutor pode corrigi-los antes de iniciar. A confirmação das autorizações não é persistida e deve ser renovada em cada oficina.

O sistema gera códigos temporários para os dois participantes. Nomes não são solicitados.

Cada criança recebe um convite de assentimento em linguagem simples. Se qualquer participante recusar, o coletor encerra sem impedir a participação pedagógica da dupla.

O professor Jadsonlee é, neste momento, a referência pedagógica informada para a definição das atividades e da rubrica. Isso não o torna automaticamente controlador dos dados ou responsável ético pelo estudo; essas funções precisam ser formalmente definidas pela instituição.

### 5.2 Pré-oficina

A idade individual não é solicitada pelo PulseLab. A faixa etária atendida deve
ser definida no protocolo e nos critérios institucionais da oficina, sem criar
uma etapa adicional de resposta para cada participante.

Cada participante responde individualmente:

1. **Experiência prévia**  
   “Antes de hoje, você já tinha montado ou programado um robô?”
   - Nunca
   - Uma vez
   - Algumas vezes
   - Muitas vezes

2. **Autoeficácia inicial**  
   “Eu acho que consigo fazer um robô cumprir uma missão.”
   - Discordo muito
   - Discordo
   - Concordo
   - Concordo muito

3. **Conhecimento específico**  
   De três a cinco itens alinhados ao objetivo da oficina. Esses itens ainda não foram definidos e não aparecem na interface 1.4.0.

### 5.3 Checkpoints de 20 e 40 minutos

Cada participante responde individualmente, sem visualizar a resposta da dupla:

1. **Esforço mental**  
   “Quanto você precisou pensar para fazer a parte em que estava agora?”
   - Muito pouco
   - Pouco
   - Bastante
   - Muito

2. **Situação da dupla**  
   “Neste momento, como vocês estão?”
   - Avançando sem ajuda
   - Avançando, mas com dúvida
   - Tentando, mas sem conseguir avançar
   - Precisamos de ajuda agora

3. **Colaboração**, aplicada aos 40 minutos por padrão  
   “Desde a última pergunta, nós dois tivemos oportunidade de dar ideias e participar da tarefa.”
   - Nunca
   - Algumas vezes
   - Quase sempre
   - Sempre

Selecionar “precisamos de ajuda agora” gera um alerta ao instrutor. A resposta não deve ser usada para negar ou atrasar apoio pedagógico.

Os papéis devem ser alternados entre os checkpoints, para que mais de uma criança tenha oportunidade de programar e montar. O evento precisa registrar o papel exercido naquele momento, e não apenas o papel inicial.

### 5.4 Encerramento

O instrutor registra:

- desempenho da missão, de 0 a 3;
- quantidade aproximada de intervenções;
- principal dificuldade: montagem, lógica, sensor, problema técnico, colaboração ou outra.

Cada participante responde:

1. **Compreensão percebida**  
   “Eu conseguiria explicar para outra pessoa como fizemos o robô funcionar.”
   - Discordo muito
   - Discordo
   - Concordo
   - Concordo muito

2. **Afetos**, escolhendo uma ou duas opções  
   Curioso, confiante, animado, frustrado, cansado ou indiferente.

3. **Intenção de retorno**  
   “Você gostaria de participar de outra oficina de robótica?”
   - Não
   - Talvez não
   - Talvez sim
   - Sim

4. **Conhecimento específico pós-oficina**  
   Itens equivalentes ao pré-teste, ainda pendentes de definição.

Em qualquer questionário, a criança pode selecionar “Prefiro não responder”.

O quiz e a corrida devem seguir uma sequência padronizada. Recomenda-se registrar, separadamente, acerto, tempo, conclusão da missão e participação de cada criança. “Chegar primeiro” é um indicador competitivo e pode ser influenciado por velocidade, montagem ou condições físicas; por isso não deve ser o único critério de aprendizagem.

## 6. Estrutura analítica

As observações estão agrupadas:

```text
Escola
└── Oficina
    └── Dupla
        └── Participante
            ├── pré
            ├── checkpoint 20
            ├── checkpoint 40
            └── pós
```

O banco usa uma linha por participante e evento. `participant_id` é um pseudônimo temporário; `event_id` é único e permite reenvio offline sem duplicação.

## 7. Desfechos

### Primário recomendado

Desempenho da dupla na missão autônoma, medido por uma rubrica padronizada de execução, explicação e participação. O desfecho é inicialmente de nível da dupla, porque o robô e a missão são compartilhados.

Para transformar a pesquisa em avaliação individual, acrescentar uma explicação curta de cada criança: “explique o que fez o robô se mover” ou “mostre qual parte do programa controla esta ação”. Essa resposta pode receber uma rubrica individual de 0 a 3.

### Secundários

- esforço mental percebido;
- colaboração percebida;
- desempenho da missão;
- número de intervenções;
- compreensão percebida;
- afetos;
- intenção de retorno;
- ganho de conhecimento imediato, quando os itens forem definidos;
- completude e latência da coleta.

## 8. Plano inicial de análise

- Esforço aos 20/40 minutos: modelo ordinal de efeitos mistos.
- Bloqueio e ajuda: regressão logística multinível.
- Desempenho: modelo ajustado por experiência prévia, papel e atividade.
- Pré/pós de conhecimento: modelo misto ou análise pareada, sem alegação causal na ausência de comparador.
- Respostas ausentes: descrever separadamente `declined` e `timeout`.
- Escola, oficina e dupla: tratar como níveis de agrupamento quando a amostra permitir.

O estado da dupla (`progress_state`) continua sendo um desfecho de processo importante, mas passa a ser secundário em relação ao desempenho da missão. Se o foco acadêmico mudar para mediação e bloqueio, ele poderá se tornar o primário em um estudo específico de processo.

Médias e Pearson podem ser usados apenas como exploração. Screenshots, inatividade e tamanho de arquivo são evidências auxiliares e não medidas diretas de aprendizagem.

## 9. Privacidade e ética

- A coleta científica depende de aprovação ética aplicável.
- Consentimento do responsável e assentimento da criança são processos distintos.
- Recusar a pesquisa não altera a participação na oficina.
- O banco analítico não recebe nomes.
- Screenshots são limitados à janela do SPIKE e armazenados em bucket privado.
- O cache fica no perfil local do usuário.
- Acesso, retenção, descarte e eventual publicação devem ser formalmente definidos.
- Resultados divulgados não podem permitir reidentificação de escolas, turmas ou crianças.

## 10. Plano de validação do instrumento

1. Revisão de conteúdo por especialistas.
2. Entrevistas cognitivas com crianças da faixa etária atendida.
3. Piloto em poucas oficinas.
4. Avaliação de tempo, compreensão, recusas, timeouts e efeito teto/piso.
5. Comparação de bloqueio relatado com ajuda e desempenho observados.
6. Revisão dos itens e congelamento de uma versão.
7. Cálculo da amostra e registro prévio do plano confirmatório.

Até a conclusão desse processo, usar a denominação **instrumento experimental em processo de validação**.

## 11. Decisões necessárias antes da coleta definitiva

Estas respostas são necessárias para completar o método e implementar o pré/pós de conhecimento:

1. Quais idades e anos escolares participam?
2. A duração de todas as oficinas é a mesma? Quais são suas etapas?
3. Quais são os objetivos de aprendizagem de cada `activity_id`?
4. Que conceito deve ser demonstrado ao final de cada atividade?
5. As duplas sempre têm duas crianças? Existem trios?
6. Os papéis de programação e montagem são trocados? Em qual momento?
7. O que caracteriza missão concluída em cada atividade?
8. Qual é o protocolo de intervenção quando uma dupla pede ajuda?
9. Quais códigos padronizados identificarão escola, turma e oficina?
10. A proposta inicial é usar desempenho da missão autônoma como desfecho primário; confirmar se o estudo deve priorizar desempenho, bloqueio ou ganho de conhecimento.
11. Haverá grupo comparador, implantação escalonada ou somente estudo observacional?
12. Quem é o controlador dos dados e quem terá acesso às imagens?
13. Por quanto tempo eventos e screenshots serão armazenados?
14. Screenshots são realmente necessários para a pergunta principal?
15. Qual CEP avaliará o protocolo e como serão geridos consentimento e assentimento?
16. Qual é a idade mínima dos participantes?
17. Quando houver três crianças, elas compartilham um computador? Qual será o terceiro papel?
18. Em qual checkpoint os papéis serão trocados?
19. Quais critérios objetivos compõem a rubrica do quiz, da corrida e da explicação individual?
20. Qual prazo de retenção dos eventos e screenshots será adotado?

## 12. Critérios para iniciar o piloto

- [ ] Questões 1–20 acima respondidas.
- [ ] Fluxo testado em Windows 10/11 com PowerShell 5.1.
- [ ] Schema 1.4.0 aplicado em ambiente de teste.
- [ ] Bucket confirmado como privado.
- [ ] Procedimentos de consentimento e assentimento aprovados.
- [ ] Instrutores treinados na rubrica e no protocolo de ajuda.
- [ ] Dados de teste removidos antes da coleta real.
- [ ] Dashboard identificado como simulado ou conectado a dados reais.
