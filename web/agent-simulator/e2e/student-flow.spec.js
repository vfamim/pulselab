import { expect, test } from "@playwright/test";

async function choose(page, question, answer) {
  const fieldset = page.getByRole("group", { name: question });
  await fieldset.getByRole("button", { name: answer }).click();
}

async function answerPre(page) {
  await choose(page, /Quanto o grupo já trabalhou/, /Nunca usamos/);
  await choose(page, /Quão confiantes vocês estão/, /Confiantes$/);
  await page.getByRole("button", { name: "Começar Atividade!" }).click();
}

async function answerCheckpoint(page) {
  await choose(page, /Quanto esforço mental/, /Pouco$/);
  await choose(page, /Em que situação o grupo está/, /Avançando/);
  await choose(page, /Como o grupo está trabalhando junto/, /Decidimos juntos/);
  await page.getByRole("button", { name: "Salvar e continuar" }).click();
}

async function answerPost(page) {
  await choose(page, /Quanto o grupo entende/, /Conseguimos explicar/);
  await choose(page, /Quanto vocês gostariam de participar/, /Gostaríamos muito/);
  await choose(page, /Qual palavra melhor resume/, /Orgulho e confiança/);
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
