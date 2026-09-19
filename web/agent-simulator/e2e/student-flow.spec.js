import { expect, test } from "@playwright/test";

async function choose(page, question, answer) {
  const fieldset = page.getByRole("group", { name: question });
  await fieldset.getByRole("button", { name: answer }).click();
}

async function answerPre(page) {
  await choose(page, /programou robôs/i, /Primeira vez/i);
  await choose(page, /confiança/i, /Confiantes/i);
  await page.getByRole("button", { name: "Começar Atividade!" }).click();
}

async function answerCheckpoint(page) {
  await choose(page, /dificuldade/i, /Normal/i);
  await choose(page, /robô e o código/i, /Avançando/i);
  await choose(page, /dividindo as tarefas/i, /Em equipe/i);
  await page.getByRole("button", { name: "Salvar e continuar" }).click();
}

async function answerPost(page) {
  await choose(page, /entenderam sobre o que o robô/i, /Totalmente/i);
  await choose(page, /outra oficina/i, /Quero sempre/i);
  await choose(page, /emoji melhor resume/i, /Orgulho/i);
  await page.getByRole("button", { name: "Concluir Oficina" }).click();
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    if (!sessionStorage.getItem("pulselab-test-started")) {
      localStorage.clear();
      sessionStorage.setItem("pulselab-test-started", "1");
    }
  });
  await page.goto("/alunos/?lab=1");
});

test("conclui a jornada rápida da oficina com checkpoints e finalização", async ({ page }) => {
  // Tela Pré (Início imediato sem burocracia de cadastro)
  await expect(page.getByRole("heading", { name: /Como vocês chegam para esta oficina\?/ })).toBeVisible();
  await answerPre(page);

  // Tela Atividade
  await expect(page.getByRole("heading", { name: "Pode focar no projeto do SPIKE" })).toBeVisible();

  // Checkpoint de 20 min via controles do lab
  await page.getByRole("button", { name: "⏩ Check-in 20m" }).click();
  await page.getByRole("button", { name: "Responder Check-in Agora (30s)" }).click();
  await expect(page.getByRole("heading", { name: "Como está indo o projeto?" })).toBeVisible();
  await answerCheckpoint(page);

  // Volta para a Atividade
  await expect(page.getByRole("heading", { name: "Pode focar no projeto do SPIKE" })).toBeVisible();

  // Checkpoint de 40 min via controles do lab
  await page.getByRole("button", { name: "⏩ Check-in 40m" }).click();
  await page.getByRole("button", { name: "Responder Check-in Agora (30s)" }).click();
  await expect(page.getByRole("heading", { name: "Como está indo o projeto?" })).toBeVisible();
  await answerCheckpoint(page);

  // Tela Pós (Finalização)
  await expect(page.getByRole("heading", { name: "Como foi a experiência do grupo?" })).toBeVisible();
  await answerPost(page);

  // Tela Conclusão
  await expect(page.getByRole("heading", { name: "Oficina concluída com sucesso!" })).toBeVisible();
  await expect(page.getByText("Parabéns pelo trabalho!")).toBeVisible();
});

test("retoma do ponto salvo depois de recarregar a página", async ({ page }) => {
  await expect(page.getByRole("heading", { name: /Como vocês chegam para esta oficina\?/ })).toBeVisible();
  await answerPre(page);
  await expect(page.getByRole("heading", { name: "Pode focar no projeto do SPIKE" })).toBeVisible();

  await page.reload();
  await expect(page.getByRole("heading", { name: "Pode focar no projeto do SPIKE" })).toBeVisible();
});

test("carrega a aplicação instalada mesmo sem internet", async ({ page, context }) => {
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await expect(page.getByRole("heading", { name: /Como vocês chegam para esta oficina\?/ })).toBeVisible();

  await context.setOffline(true);
  await page.reload({ waitUntil: "domcontentloaded" });
  await expect(page.getByRole("heading", { name: /Como vocês chegam para esta oficina\?/ })).toBeVisible();
  await expect(page.getByText("Modo acelerado para testes")).toBeVisible();

  await context.setOffline(false);
});

test("permite forçar avanço, testar alerta com modal e reiniciar a oficina", async ({ page }) => {
  // Preencher teste na tela pré
  await page.getByRole("button", { name: "✨ Preencher teste" }).click();
  await page.getByRole("button", { name: "Começar Atividade!" }).click();
  await expect(page.getByRole("heading", { name: "Pode focar no projeto do SPIKE" })).toBeVisible();

  // Testar disparo de som e modal de alerta
  await page.getByRole("button", { name: "🔔 Testar Som & Pop-up" }).click();
  await expect(page.getByRole("heading", { name: /Hora do Check-in de 20 minutos!/ })).toBeVisible();

  // Clicar no botão do modal para abrir o checkpoint
  await page.getByRole("button", { name: "Responder Check-in Agora (30s)" }).click();
  await expect(page.getByRole("heading", { name: "Como está indo o projeto?" })).toBeVisible();

  // Reiniciar a oficina a qualquer momento
  page.on("dialog", (dialog) => dialog.accept());
  await page.getByRole("button", { name: "🔄 Reiniciar", exact: true }).click();
  await expect(page.getByRole("heading", { name: /Como vocês chegam para esta oficina\?/ })).toBeVisible();
});

test("permite configurar escola e turma através do modal de contexto", async ({ page }) => {
  // Abrir modal de contexto via botão do topo
  await page.getByRole("button", { name: "🏫 Turma" }).click();
  await expect(page.getByRole("heading", { name: "⚙️ Configurar Escola & Turma" })).toBeVisible();

  // Alterar escola e salvar
  const schoolInput = page.locator("input").nth(2);
  await schoolInput.fill("ESCOLA-EXPERIMENTAL-01");
  await page.getByRole("button", { name: "💾 Salvar Configurações" }).click();

  // Confirmar que o modal fechou e o toast foi disparado
  await expect(page.getByRole("heading", { name: "⚙️ Configurar Escola & Turma" })).not.toBeVisible();
  await expect(page.getByText("Configurações da turma salvas com sucesso!")).toBeVisible();
});

test("permite recusa informada da pesquisa e avanço direto para a atividade", async ({ page }) => {
  await expect(page.getByRole("heading", { name: /Como vocês chegam para esta oficina\?/ })).toBeVisible();

  // Clicar em recusa voluntária
  await page.getByRole("button", { name: "Prefiro não responder a pesquisa" }).click();

  // Deve ir diretamente para a atividade sem forçar questionários
  await expect(page.getByRole("heading", { name: "Pode focar no projeto do SPIKE" })).toBeVisible();
  await expect(page.getByText(/Oficina liberada em modo livre/)).toBeVisible();
});
