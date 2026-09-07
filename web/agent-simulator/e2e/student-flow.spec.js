import { expect, test } from "@playwright/test";

async function choose(page, question, answer) {
  const fieldset = page.getByRole("group", { name: question });
  await fieldset.getByRole("button", { name: answer }).click();
}

async function answerPre(page) {
  await choose(page, /Quanto você já trabalhou/, /Nunca usei/);
  await choose(page, /Quão confiante você está para começar/, /Confiante$/);
  await page.getByRole("button", { name: "Salvar e continuar" }).click();
}

async function answerCheckpoint(page) {
  await choose(page, /Quanto esforço mental/, /Pouco$/);
  await choose(page, /Em que situação o grupo está/, /Avançando/);
  await choose(page, /Como o grupo está trabalhando junto/, /Decidimos juntos/);
  await choose(page, /Qual papel você está fazendo/, /Computador e programação/);
  await page.getByRole("button", { name: "Salvar meu check-in" }).click();
}

async function answerPost(page) {
  await choose(page, /Quanto você entende agora/, /Consigo explicar/);
  await choose(page, /Quanto você gostaria de participar/, /Gostaria muito/);
  await choose(page, /Qual palavra combina mais/, /Orgulho e confiança/);
  await page.getByRole("button", { name: "Salvar resposta final" }).click();
}

async function handTo(page, participant) {
  await page.getByRole("button", { name: new RegExp(`Sou o participante ${participant}`) }).click();
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

test("conclui a jornada de dois alunos sem trilha do instrutor", async ({ page }) => {
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Chamar participante A" }).click();

  await expect(page.getByText("não tiramos fotos da tela")).toBeVisible();
  await page.getByRole("button", { name: "Sim, quero participar" }).click();
  await handTo(page, "B");
  await page.getByRole("button", { name: "Sim, quero participar" }).click();
  await handTo(page, "A");

  await answerPre(page);
  await handTo(page, "B");
  await answerPre(page);

  await expect(page.getByRole("heading", { name: "Pode voltar para o projeto" })).toBeVisible();
  await page.getByRole("button", { name: "Abrir checkpoint de 20 min" }).click();
  await handTo(page, "A");
  await answerCheckpoint(page);
  await handTo(page, "B");
  await answerCheckpoint(page);

  await page.getByRole("button", { name: "Trocamos os papéis" }).click();
  await page.getByRole("button", { name: "Abrir checkpoint de 40 min" }).click();
  await handTo(page, "A");
  await answerCheckpoint(page);
  await handTo(page, "B");
  await answerCheckpoint(page);

  await page.getByRole("button", { name: "Chamar participante A" }).click();
  await handTo(page, "A");
  await answerPost(page);
  await handTo(page, "B");
  await answerPost(page);

  await expect(page.getByRole("heading", { name: "As respostas do grupo foram salvas" })).toBeVisible();
  await expect(page.getByText("Obrigado por participar.")).toBeVisible();
});

test("não cria eventos quando um aluno recusa", async ({ page }) => {
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Chamar participante A" }).click();
  await page.getByRole("button", { name: "Prefiro não participar" }).click();

  await expect(page.getByRole("heading", { name: "A participação foi encerrada" })).toBeVisible();
  await expect(page.getByText("0 eventos")).toBeVisible();
});

test("retoma do ponto salvo depois de recarregar a página", async ({ page }) => {
  await page.getByRole("checkbox").check();
  await page.getByRole("button", { name: "Chamar participante A" }).click();
  await page.getByRole("button", { name: "Sim, quero participar" }).click();
  await expect(page.getByRole("heading", { name: "Agora é a vez do participante B" })).toBeVisible();

  await page.reload();
  await page.getByRole("button", { name: "Continuar sessão salva" }).click();
  await expect(page.getByRole("heading", { name: "Agora é a vez do participante B" })).toBeVisible();
});

test("carrega a aplicação instalada mesmo sem internet", async ({ page, context }) => {
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await expect(page.getByRole("heading", { name: "Deixe a atividade pronta para os alunos" })).toBeVisible();

  await context.setOffline(true);
  await page.reload({ waitUntil: "domcontentloaded" });
  await expect(page.getByRole("heading", { name: "Deixe a atividade pronta para os alunos" })).toBeVisible();
  await expect(page.getByText("Modo acelerado para testes locais")).toBeVisible();

  await context.setOffline(false);
});
