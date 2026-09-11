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
  await expect(page.getByRole("heading", { name: "Deixe a atividade pronta para os alunos" })).toBeVisible();
  await page.getByRole("button", { name: "Iniciar Oficina" }).click();

  // Tela Pré (Início)
  await expect(page.getByRole("heading", { name: "Como o grupo chega para esta oficina?" })).toBeVisible();
  await answerPre(page);

  // Tela Atividade
  await expect(page.getByRole("heading", { name: "Pode focar no projeto do SPIKE" })).toBeVisible();

  // Checkpoint de 20 min
  await page.getByRole("button", { name: "Abrir checkpoint de 20 min" }).click();
  await expect(page.getByRole("heading", { name: "Como está indo o projeto?" })).toBeVisible();
  await answerCheckpoint(page);

  // Volta para a Atividade (sem tela de troca de papéis)
  await expect(page.getByRole("heading", { name: "Pode focar no projeto do SPIKE" })).toBeVisible();

  // Checkpoint de 40 min
  await page.getByRole("button", { name: "Abrir checkpoint de 40 min" }).click();
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
  await page.getByRole("button", { name: "Iniciar Oficina" }).click();
  await expect(page.getByRole("heading", { name: "Como o grupo chega para esta oficina?" })).toBeVisible();

  await page.reload();
  await page.getByRole("button", { name: "Continuar sessão salva" }).click();
  await expect(page.getByRole("heading", { name: "Como o grupo chega para esta oficina?" })).toBeVisible();
});

test("carrega a aplicação instalada mesmo sem internet", async ({ page, context }) => {
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await expect(page.getByRole("heading", { name: "Deixe a atividade pronta para os alunos" })).toBeVisible();

  await context.setOffline(true);
  await page.reload({ waitUntil: "domcontentloaded" });
  await expect(page.getByRole("heading", { name: "Deixe a atividade pronta para os alunos" })).toBeVisible();
  await expect(page.getByText("Modo acelerado para testes")).toBeVisible();

  await context.setOffline(false);
});
