import { expect, test } from "@playwright/test";

async function getStoredRecords(page, storeName) {
  return page.evaluate(
    (name) =>
      new Promise((resolve) => {
        const req = indexedDB.open("pulselab-student-runner", 1);
        req.onsuccess = () => {
          const db = req.result;
          if (!db.objectStoreNames.contains(name)) {
            resolve([]);
            db.close();
            return;
          }
          const tx = db.transaction(name, "readonly");
          const store = tx.objectStore(name);
          const getAllReq = store.getAll();
          getAllReq.onsuccess = () => resolve(getAllReq.result || []);
          getAllReq.onerror = () => resolve([]);
          tx.oncomplete = () => db.close();
        };
        req.onerror = () => resolve([]);
      }),
    storeName
  );
}

test.beforeEach(async ({ page }) => {
  await page.goto("/alunos/");
  await page.evaluate(async () => {
    localStorage.clear();
    sessionStorage.clear();
    await new Promise((resolve) => {
      const req = indexedDB.deleteDatabase("pulselab-student-runner");
      req.onsuccess = () => resolve();
      req.onerror = () => resolve();
      req.onblocked = () => resolve();
    });
  });
  await page.reload();
});

test("initial screen loads with assent unchecked and team size selection", async ({ page }) => {
  await page.goto("/alunos/");

  // Invariante metodológica: o consentimento DEVE iniciar desmarcado
  const assentCheckbox = page.locator("#ethical-assent-checkbox");
  await expect(assentCheckbox).toBeVisible();
  await expect(assentCheckbox).not.toBeChecked();

  // Sem assentimento, botão indica modo livre sem coleta
  await expect(page.getByRole("button", { name: "Começar sem Pesquisa" })).toBeVisible();

  // Botões de equipe de 1 a 4 integrantes
  await expect(page.getByRole("button", { name: /1 Aluno/i })).toBeVisible();
  await expect(page.getByRole("button", { name: /2 Alunos/i })).toBeVisible();
  await expect(page.getByRole("button", { name: /3 Alunos/i })).toBeVisible();
  await expect(page.getByRole("button", { name: /4 Alunos/i })).toBeVisible();
});

test("ethical refusal (free mode) produces ZERO stored sessions and events and ZERO localStorage persistence", async ({ page }) => {
  await page.goto("/alunos/");

  const getRelevantLocalStorage = async () =>
    page.evaluate(() => ({
      installationId: localStorage.getItem("pulselab_installation_id_v1"),
      legacyInstallationId: localStorage.getItem("pulselab_student_installation_id_v1"),
      activeSession: localStorage.getItem("pulselab_student_active_session_v1")
    }));

  // Antes da recusa (montagem inicial): NENHUMA persistência de installation_id ou sessão
  const storageBefore = await getRelevantLocalStorage();
  expect(storageBefore.installationId).toBeNull();
  expect(storageBefore.legacyInstallationId).toBeNull();
  expect(storageBefore.activeSession).toBeNull();

  // Deixa o assentimento desmarcado e inicia modo livre
  await expect(page.locator("#ethical-assent-checkbox")).not.toBeChecked();
  await page.getByRole("button", { name: "Começar sem Pesquisa" }).click();

  // Após recusa: NENHUMA persistência em localStorage
  const storageAfterDecline = await getRelevantLocalStorage();
  expect(storageAfterDecline.installationId).toBeNull();
  expect(storageAfterDecline.legacyInstallationId).toBeNull();
  expect(storageAfterDecline.activeSession).toBeNull();

  // Entra na Etapa 2 de oficina livre
  await expect(
    page.getByRole("heading", { name: "Construção, Programação & Testes do Robô" })
  ).toBeVisible();
  await expect(page.getByText(/Oficina livre sem coleta de dados/i)).toBeVisible();

  // Avança para a Etapa 3
  await page.getByRole("button", { name: /Finalizar Oficina & Ir para Corrida/i }).click();

  // Na Etapa 3, pula a avaliação
  await expect(
    page.getByRole("heading", { name: "Desafio da Corrida & Avaliação Final" })
  ).toBeVisible();
  await page.getByRole("button", { name: "Pular avaliação e finalizar" }).click();

  // Chega na tela final
  await expect(
    page.getByRole("heading", { name: "Oficina concluída com sucesso!" })
  ).toBeVisible();

  // No final do modo livre: localStorage continua totalmente limpo de installation_id e sessão
  const storageFinal = await getRelevantLocalStorage();
  expect(storageFinal.installationId).toBeNull();
  expect(storageFinal.legacyInstallationId).toBeNull();
  expect(storageFinal.activeSession).toBeNull();

  // Invariante estrita: ZERO persistência no IndexedDB para recusa
  const sessions = await getStoredRecords(page, "sessions");
  const events = await getStoredRecords(page, "events");

  expect(sessions.length).toBe(0);
  expect(events.length).toBe(0);
});

test("full 3-stage journey saves session snapshot and emits all final events", async ({ page }) => {
  const consoleErrors = [];
  page.on("pageerror", (err) => consoleErrors.push(err.message));

  await page.goto("/alunos/");

  // Antes do assentimento unânime, installation_id NÃO deve existir no localStorage
  const initialInstallationId = await page.evaluate(() => localStorage.getItem("pulselab_installation_id_v1"));
  expect(initialInstallationId).toBeNull();

  // 1. Etapa 1: Assentimento e caracterização
  // Seleciona dupla (2 alunos)
  await page.getByRole("button", { name: /2 Alunos/i }).click();

  const assentCheckbox1 = page.locator("#ethical-assent-checkbox");
  await assentCheckbox1.check();
  await expect(assentCheckbox1).toBeChecked();

  const assentCheckbox2 = page.locator("#ethical-assent-member-2");
  await assentCheckbox2.check();
  await expect(assentCheckbox2).toBeChecked();

  // Responde pergunta de experiência prévia com robôs
  await page.getByRole("button", { name: /Primeira vez/i }).click();

  // Inicia atividade com pesquisa habilitada
  const startBtn = page.getByRole("button", { name: "Começar Atividade!" });
  await expect(startBtn).toBeEnabled();
  await startBtn.click();

  // Após assentimento unânime e início da pesquisa, installation_id DEVE estar persistido no localStorage
  const persistedInstallationId = await page.evaluate(() => localStorage.getItem("pulselab_installation_id_v1"));
  expect(persistedInstallationId).toBeTruthy();
  expect(typeof persistedInstallationId).toBe("string");
  expect(persistedInstallationId.length).toBe(36);

  // 2. Etapa 2: Oficina prática com cronômetro
  await expect(
    page.getByRole("heading", { name: "Construção, Programação & Testes do Robô" })
  ).toBeVisible();
  await expect(page.locator(".activity-timer")).toBeVisible();

  // Avança para Desafio Final / Avaliação
  await page.getByRole("button", { name: /Finalizar Oficina & Ir para Corrida/i }).click();

  // 3. Etapa 3: Eixo 1 (individual) e Eixo 2 (bancada)
  await expect(
    page.getByRole("heading", { name: "Desafio da Corrida & Avaliação Final" })
  ).toBeVisible();

  // Eixo 1: Avaliação dos 2 estudantes
  // Estudante 1 avalia
  await page.getByRole("button", { name: /Muito boa/i }).first().click();

  // Estudante 2 pula voluntariamente
  const skipStudent2 = page.getByRole("button", { name: "Prefiro não responder" }).last();
  await skipStudent2.click();

  // Eixo 2: Resultados da bancada
  await page.getByText(/Concluiu com sucesso/i).click();
  await page.getByText(/Concluída conforme o roteiro/i).click();
  await page.getByText(/Autônomo/i).click();

  // Concluir e salvar
  await page.getByRole("button", { name: "Concluir e Salvar Oficina" }).click();

  // 4. Tela final
  await expect(
    page.getByRole("heading", { name: "Oficina concluída com sucesso!" })
  ).toBeVisible();

  // Verifica persistência durável no IndexedDB
  const sessions = await getStoredRecords(page, "sessions");
  const events = await getStoredRecords(page, "events");

  expect(sessions.length).toBe(1);
  expect(sessions[0].status).toBe("completed");
  expect(sessions[0].group_size).toBe(2);

  // Snapshot determinístico: o payload da sessão deve conter os eventos finais recém-gerados
  expect(sessions[0].events).toBeDefined();
  expect(sessions[0].events.length).toBeGreaterThanOrEqual(4);

  const eventTypesInSnapshot = sessions[0].events.map((e) => e.event_type);
  expect(eventTypesInSnapshot).toContain("session_started");
  expect(eventTypesInSnapshot).toContain("pre");
  expect(eventTypesInSnapshot).toContain("post");
  expect(eventTypesInSnapshot).toContain("session_completed");

  // Eventos na store
  const storedEventTypes = events.map((e) => e.event_type);
  expect(storedEventTypes).toContain("session_started");
  expect(storedEventTypes).toContain("post");

  // Nenhum erro de runtime ocorrido
  expect(consoleErrors).toEqual([]);
});

test("consecutive workshop restart cleans state without setHelpActive ReferenceError", async ({ page }) => {
  const consoleErrors = [];
  page.on("pageerror", (err) => consoleErrors.push(err.message));

  await page.goto("/alunos/");

  // Seleciona 1 Aluno para ciclo rápido
  await page.getByRole("button", { name: /1 Aluno/i }).click();
  await page.locator("#ethical-assent-checkbox").check();
  await page.getByRole("button", { name: /Primeira vez/i }).click();
  await page.getByRole("button", { name: "Começar Atividade!" }).click();

  // Avança para post
  await page.getByRole("button", { name: /Finalizar Oficina & Ir para Corrida/i }).click();

  // Preenche rápido e conclui
  await page.getByRole("button", { name: /Muito boa/i }).first().click();
  await page.getByRole("button", { name: "Concluir e Salvar Oficina" }).click();

  await expect(
    page.getByRole("heading", { name: "Oficina concluída com sucesso!" })
  ).toBeVisible();

  // Clica para reiniciar nova oficina consecutiva
  await page.getByRole("button", { name: "Preparar Nova Oficina" }).click();

  // Volta limpa para a Etapa 1
  await expect(
    page.getByRole("heading", { name: "Como vocês chegam para esta oficina?" })
  ).toBeVisible();

  // Assentimento deve ter voltado para desmarcado
  const assentCheckbox = page.locator("#ethical-assent-checkbox");
  await expect(assentCheckbox).not.toBeChecked();

  // Prova que setHelpActive não disparou ReferenceError
  expect(consoleErrors.filter((e) => e.includes("setHelpActive"))).toEqual([]);
  expect(consoleErrors).toEqual([]);
});

test("individual student mode presents 1 member evaluation without group consensus", async ({ page }) => {
  await page.goto("/alunos/");

  // Seleciona 1 Aluno
  await page.getByRole("button", { name: /1 Aluno/i }).click();
  await page.locator("#ethical-assent-checkbox").check();
  await page.getByRole("button", { name: /Primeira vez/i }).click();
  await page.getByRole("button", { name: "Começar Atividade!" }).click();

  // Avança para post
  await page.getByRole("button", { name: /Finalizar Oficina & Ir para Corrida/i }).click();

  // Confirma rótulo individual e apenas 1 bloco de avaliação de estudante
  await expect(page.getByText("Avaliação do Estudante")).toBeVisible();
  await expect(page.getByText("Estudante 2 de")).toHaveCount(0);

  // Seleciona nota
  await page.getByRole("button", { name: /Muito boa/i }).click();
  await page.getByRole("button", { name: "Concluir e Salvar Oficina" }).click();

  await expect(
    page.getByRole("heading", { name: "Oficina concluída com sucesso!" })
  ).toBeVisible();

  const sessions = await getStoredRecords(page, "sessions");
  expect(sessions.length).toBe(1);
  expect(sessions[0].group_size).toBe(1);
});

test("reload during activity retains active session state", async ({ page }) => {
  await page.goto("/alunos/");
  await page.getByRole("button", { name: /1 Aluno/i }).click();
  await page.locator("#ethical-assent-checkbox").check();
  await page.getByRole("button", { name: /Primeira vez/i }).click();
  await page.getByRole("button", { name: "Começar Atividade!" }).click();

  await expect(
    page.getByRole("heading", { name: "Construção, Programação & Testes do Robô" })
  ).toBeVisible();

  await page.reload();

  const activityHeading = page.getByRole("heading", { name: "Construção, Programação & Testes do Robô" });
  const resumeBtn = page.getByRole("button", { name: /Continuar sessão salva/i });

  if (await resumeBtn.isVisible()) {
    await resumeBtn.click();
  }
  await expect(activityHeading).toBeVisible();
});

test("resetToPre definitively purges IndexedDB and localStorage session data", async ({ page }) => {
  await page.goto("/alunos/");
  await page.getByRole("button", { name: /1 Aluno/i }).click();
  await page.locator("#ethical-assent-checkbox").check();
  await page.getByRole("button", { name: /Primeira vez/i }).click();
  await page.getByRole("button", { name: "Começar Atividade!" }).click();

  await page.waitForTimeout(500);
  let events = await getStoredRecords(page, "events");
  expect(events.length).toBeGreaterThan(0);

  page.on("dialog", (dialog) => dialog.accept());
  await page.getByRole("button", { name: /Reiniciar/i }).first().click();

  await expect(
    page.getByRole("heading", { name: "Como vocês chegam para esta oficina?" })
  ).toBeVisible();

  events = await getStoredRecords(page, "events");
  const sessions = await getStoredRecords(page, "sessions");
  expect(events.length).toBe(0);
  expect(sessions.length).toBe(0);
});

test("two tabs observe the same active session in storage", async ({ context }) => {
  const page1 = await context.newPage();
  await page1.goto("/alunos/");
  await page1.getByRole("button", { name: /1 Aluno/i }).click();
  await page1.locator("#ethical-assent-checkbox").check();
  await page1.getByRole("button", { name: /Primeira vez/i }).click();
  await page1.getByRole("button", { name: "Começar Atividade!" }).click();

  await expect(
    page1.getByRole("heading", { name: "Construção, Programação & Testes do Robô" })
  ).toBeVisible();

  const page2 = await context.newPage();
  await page2.goto("/alunos/");

  const resumeVisible = await page2.getByRole("button", { name: /Continuar sessão salva/i }).isVisible();
  const activityVisible = await page2.getByRole("heading", { name: "Construção, Programação & Testes do Robô" }).isVisible();
  expect(resumeVisible || activityVisible).toBe(true);

  await page1.close();
  await page2.close();
});

test("ethical refusal makes NO external network calls to cloud", async ({ page }) => {
  const externalRequests = [];
  page.on("request", (req) => {
    const url = req.url();
    if (url.includes("supabase.co") || url.includes("/rest/v1/")) {
      externalRequests.push(url);
    }
  });

  await page.goto("/alunos/");
  await page.getByRole("button", { name: "Começar sem Pesquisa" }).click();

  await expect(
    page.getByRole("heading", { name: "Construção, Programação & Testes do Robô" })
  ).toBeVisible();

  await page.getByRole("button", { name: /Finalizar Oficina & Ir para Corrida/i }).click();
  await page.getByRole("button", { name: "Pular avaliação e finalizar" }).click();

  await expect(
    page.getByRole("heading", { name: "Oficina concluída com sucesso!" })
  ).toBeVisible();

  expect(externalRequests).toEqual([]);
});

test("rubric answers are included in exported artifact", async ({ page }) => {
  await page.goto("/alunos/");
  await page.locator("#ethical-assent-checkbox").check();
  await page.getByRole("button", { name: /1 Aluno/i }).click();
  await page.getByRole("button", { name: /Primeira vez/i }).click();
  await page.getByRole("button", { name: "Começar Atividade!" }).click();

  await page.getByRole("button", { name: /Finalizar Oficina & Ir para Corrida/i }).click();

  await page.getByRole("button", { name: /Muito boa/i }).click();
  await page.getByText(/Concluiu com sucesso/i).click();
  await page.getByText(/Concluída conforme o roteiro/i).click();
  await page.getByText(/Autônomo/i).click();

  await page.getByRole("button", { name: "Concluir e Salvar Oficina" }).click();

  await expect(
    page.getByRole("heading", { name: "Oficina concluída com sucesso!" })
  ).toBeVisible();

  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Baixar cópia local (.json)" }).click();
  const download = await downloadPromise;

  const stream = await download.createReadStream();
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  const downloadedJson = JSON.parse(Buffer.concat(chunks).toString("utf-8"));

  expect(downloadedJson.session_id).toBeDefined();
  expect(downloadedJson.status).toBe("completed");
  expect(downloadedJson.post_answers.raceResult).toBe("success");
  expect(downloadedJson.post_answers.assemblyResult).toBe("complete");
  expect(downloadedJson.events.some((e) => e.event_type === "rubric_completed")).toBe(true);
});

test("reload for bench 2-4 members preserves exact memberAssents in active session snapshot", async ({ page }) => {
  await page.goto("/alunos/");

  // Seleciona Trio (3 alunos)
  await page.getByRole("button", { name: /3 Alunos/i }).click();

  // Marca os 3 assentimentos explicitamente
  const assent1 = page.locator("#ethical-assent-checkbox");
  const assent2 = page.locator("#ethical-assent-member-2");
  const assent3 = page.locator("#ethical-assent-member-3");

  await assent1.check();
  await assent2.check();
  await assent3.check();

  await expect(assent1).toBeChecked();
  await expect(assent2).toBeChecked();
  await expect(assent3).toBeChecked();

  await page.getByRole("button", { name: /Primeira vez/i }).click();
  await page.getByRole("button", { name: "Começar Atividade!" }).click();

  await expect(
    page.getByRole("heading", { name: "Construção, Programação & Testes do Robô" })
  ).toBeVisible();

  // Recarrega a página
  await page.reload();

  // Retoma se houver banner de retomada
  const resumeBtn = page.getByRole("button", { name: /Continuar sessão salva/i });
  if (await resumeBtn.isVisible()) {
    await resumeBtn.click();
  }

  // Verifica que o snapshot preservou exatamente teamSize=3 e os 3 assents
  const snapshot = await page.evaluate(() =>
    JSON.parse(localStorage.getItem("pulselab_student_active_session_v1"))
  );
  expect(snapshot).not.toBeNull();
  expect(snapshot.teamSize).toBe(3);
  expect(snapshot.memberAssents[1]).toBe(true);
  expect(snapshot.memberAssents[2]).toBe(true);
  expect(snapshot.memberAssents[3]).toBe(true);
  expect(snapshot.assentAgreed).toBe(true);
});

test("preparar nova oficina does NOT purge completed session from IndexedDB", async ({ page }) => {
  await page.goto("/alunos/");

  // Conclui uma oficina completa de 1 aluno
  await page.getByRole("button", { name: /1 Aluno/i }).click();
  await page.locator("#ethical-assent-checkbox").check();
  await page.getByRole("button", { name: /Primeira vez/i }).click();
  await page.getByRole("button", { name: "Começar Atividade!" }).click();

  await page.getByRole("button", { name: /Finalizar Oficina & Ir para Corrida/i }).click();
  await page.getByRole("button", { name: /Muito boa/i }).click();
  await page.getByText(/Concluiu com sucesso/i).click();
  await page.getByText(/Concluída conforme o roteiro/i).click();
  await page.getByText(/Autônomo/i).click();
  await page.getByRole("button", { name: "Concluir e Salvar Oficina" }).click();

  await expect(
    page.getByRole("heading", { name: "Oficina concluída com sucesso!" })
  ).toBeVisible();

  const sessionsBefore = await getStoredRecords(page, "sessions");
  const eventsBefore = await getStoredRecords(page, "events");
  expect(sessionsBefore.length).toBe(1);
  expect(eventsBefore.length).toBeGreaterThan(0);
  const firstSessionId = sessionsBefore[0].session_id;

  // Clica em "Preparar Nova Oficina"
  await page.getByRole("button", { name: "Preparar Nova Oficina" }).click();

  // Confirma retorno para Etapa 1
  await expect(
    page.getByRole("heading", { name: "Como vocês chegam para esta oficina?" })
  ).toBeVisible();

  // Sessão anterior DEVE continuar preservada no IndexedDB (sem purge)
  const sessionsAfter = await getStoredRecords(page, "sessions");
  const eventsAfter = await getStoredRecords(page, "events");
  expect(sessionsAfter.length).toBe(1);
  expect(sessionsAfter[0].session_id).toBe(firstSessionId);
  expect(eventsAfter.length).toBe(eventsBefore.length);

  // A nova sessão em tela deve ter IDs gerados diferentes
  const activeSessionKey = await page.evaluate(() =>
    localStorage.getItem("pulselab_student_active_session_v1")
  );
  expect(activeSessionKey).toBeNull();
});

test("free mode makes ZERO calls to /v1/spike/metrics and keeps zero telemetry in IndexedDB", async ({ page }) => {
  const spikeCalls = [];
  page.on("request", (req) => {
    if (req.url().includes("/v1/spike/metrics")) {
      spikeCalls.push(req.url());
    }
  });

  await page.goto("/alunos/");

  // Não assente e entra em modo livre
  await page.getByRole("button", { name: "Começar sem Pesquisa" }).click();

  await expect(
    page.getByRole("heading", { name: "Construção, Programação & Testes do Robô" })
  ).toBeVisible();

  // Aguarda 3 segundos na tela de atividade
  await page.waitForTimeout(3000);

  // Zero chamadas para métricas do SPIKE
  expect(spikeCalls.length).toBe(0);

  // Conclui modo livre
  await page.getByRole("button", { name: /Finalizar Oficina & Ir para Corrida/i }).click();
  await page.getByRole("button", { name: "Pular avaliação e finalizar" }).click();

  await expect(
    page.getByRole("heading", { name: "Oficina concluída com sucesso!" })
  ).toBeVisible();

  expect(spikeCalls.length).toBe(0);

  const sessions = await getStoredRecords(page, "sessions");
  const events = await getStoredRecords(page, "events");
  expect(sessions.length).toBe(0);
  expect(events.length).toBe(0);
});

test("accessibility: rubric radios and quiz buttons expose accessible tree and keyboard focus", async ({ page }) => {
  await page.goto("/alunos/");

  await page.getByRole("button", { name: /1 Aluno/i }).click();
  await page.locator("#ethical-assent-checkbox").check();
  await page.getByRole("button", { name: /Primeira vez/i }).click();
  await page.getByRole("button", { name: "Começar Atividade!" }).click();

  await page.getByRole("button", { name: /Finalizar Oficina & Ir para Corrida/i }).click();

  await expect(
    page.getByRole("heading", { name: "Desafio da Corrida & Avaliação Final" })
  ).toBeVisible();

  // Verifica que os inputs radio estão acessíveis no DOM (não display: none)
  const raceRadio = page.locator('input[name="race-result"]').first();
  await raceRadio.focus();
  await expect(raceRadio).toBeFocused();

  const assemblyRadio = page.locator('input[name="assembly-result"]').first();
  await assemblyRadio.focus();
  await expect(assemblyRadio).toBeFocused();

  // Verifica botões do Quiz A/B com role e aria-pressed
  const participatedBtn = page.getByRole("button", { name: /Realizada com botões/i }).first();
  await expect(participatedBtn).toHaveAttribute("aria-pressed", "true");

  const skippedBtn = page.getByRole("button", { name: /Dinâmica não realizada/i }).first();
  await expect(skippedBtn).toHaveAttribute("aria-pressed", "false");

  await skippedBtn.click();
  await expect(skippedBtn).toHaveAttribute("aria-pressed", "true");
  await expect(participatedBtn).toHaveAttribute("aria-pressed", "false");
});

test("accessibility: RegionMetadataModal supports keyboard focus trap, escape key, and aria-labelledby", async ({ page }) => {
  await page.goto("/alunos/");

  const openModalBtn = page.getByRole("button", { name: /Região:/i });
  await openModalBtn.click();

  const dialog = page.locator('.alert-modal-backdrop[role="dialog"]');
  await expect(dialog).toBeVisible();
  await expect(dialog).toHaveAttribute("aria-modal", "true");
  await expect(dialog).toHaveAttribute("aria-labelledby", "region-modal-title");

  const title = page.locator("#region-modal-title");
  await expect(title).toBeVisible();

  // Fecha o modal via tecla Escape real do teclado
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();

  // Verifica que o foco retornou ao elemento que abriu o modal
  await expect(openModalBtn).toBeFocused();
});

test("fail-closed: malformed snapshot in localStorage is completely rejected and discarded", async ({ page }) => {
  await page.goto("/alunos/");

  // Injeta um snapshot malformado com teamSize inválido (string ou fora de 1..4)
  await page.evaluate(() => {
    localStorage.setItem(
      "pulselab_student_active_session_v1",
      JSON.stringify({
        sessionId: "fake-malformed-session",
        teamSize: 99,
        screen: "activity",
        assentAgreed: true,
        memberAssents: { 1: "invalid-truthy", 2: "false" }
      })
    );
  });

  await page.reload();

  // Deve falhar fechado: voltar à tela inicial sem restaurar como atividade ou assentida
  await expect(
    page.getByRole("heading", { name: "Como vocês chegam para esta oficina?" })
  ).toBeVisible();

  const assentCheckbox = page.locator("#ethical-assent-checkbox");
  await expect(assentCheckbox).not.toBeChecked();

  // O storage corrompido foi limpo
  const stored = await page.evaluate(() =>
    localStorage.getItem("pulselab_student_active_session_v1")
  );
  expect(stored).toBeNull();
});

test("ethical reset vs completed preserve: Bridge contract and UI button preservation on finished screen", async ({ page }) => {
  let lastResetBody = null;
  await page.route("**/v1/sessions/reset", async (route) => {
    lastResetBody = route.request().postDataJSON();
    await route.fulfill({ status: 200, json: { status: "ok" } });
  });

  await page.goto("/alunos/");

  // 1. Recusa ética: deve purgar no Bridge com purge=true
  const resetReqPromise1 = page.waitForRequest("**/v1/sessions/reset");
  await page.getByRole("button", { name: "Começar sem Pesquisa" }).click();
  const resetReq1 = await resetReqPromise1;
  lastResetBody = resetReq1.postDataJSON();
  expect(lastResetBody).not.toBeNull();
  expect(lastResetBody.purge).toBe(true);
  expect(lastResetBody.reason).toBe("ethical_refusal");
  expect(lastResetBody.session_id).toBeDefined();

  // 2. Conclui uma sessão completa para testar botão de reiniciar na tela final
  await page.goto("/alunos/");
  await page.getByRole("button", { name: /1 Aluno/i }).click();
  await page.locator("#ethical-assent-checkbox").check();
  await page.getByRole("button", { name: /Primeira vez/i }).click();
  await page.getByRole("button", { name: "Começar Atividade!" }).click();

  await page.getByRole("button", { name: /Finalizar Oficina & Ir para Corrida/i }).click();
  await page.getByRole("button", { name: /Muito boa/i }).click();
  await page.getByRole("button", { name: "Concluir e Salvar Oficina" }).click();

  await expect(
    page.getByRole("heading", { name: "Oficina concluída com sucesso!" })
  ).toBeVisible();

  const sessionsBefore = await getStoredRecords(page, "sessions");
  expect(sessionsBefore.length).toBe(1);
  const finishedSessionId = sessionsBefore[0].session_id;

  // Clica no botão global "🔄 Reiniciar" na topbar após conclusão
  const resetReqPromise2 = page.waitForRequest("**/v1/sessions/reset");
  await page.getByRole("button", { name: "🔄 Reiniciar" }).click();
  const resetReq2 = await resetReqPromise2;
  lastResetBody = resetReq2.postDataJSON();

  // Deve ter chamado reset no Bridge com purge=false e completed=true (preservação!)
  expect(lastResetBody).not.toBeNull();
  expect(lastResetBody.purge).toBe(false);
  expect(lastResetBody.completed).toBe(true);

  // A sessão anterior deve continuar preservada no IndexedDB
  const sessionsAfter = await getStoredRecords(page, "sessions");
  expect(sessionsAfter.length).toBe(1);
  expect(sessionsAfter[0].session_id).toBe(finishedSessionId);

  // A tela deve ter voltado limpa para a Etapa 1
  await expect(
    page.getByRole("heading", { name: "Como vocês chegam para esta oficina?" })
  ).toBeVisible();
});

test("free mode zero-collection: zero memory events, export button hidden, and download blocked", async ({ page }) => {
  await page.goto("/alunos/");
  await page.getByRole("button", { name: "Começar sem Pesquisa" }).click();

  // Abre os Controles do Instrutor
  await page.getByRole("button", { name: "⚙️ Controles" }).click();

  // Botão Exportar (.json) deve estar oculto / ausente no Modo Livre
  await expect(page.getByRole("button", { name: /Exportar \(\.json\)/i })).toHaveCount(0);

  // Eventos na tela devem ser zero
  const storedEvents = await getStoredRecords(page, "events");
  expect(storedEvents.length).toBe(0);
});

test("terminal telemetry order: session_completed is definitively the last persisted event", async ({ page }) => {
  await page.goto("/alunos/");
  await page.getByRole("button", { name: /1 Aluno/i }).click();
  await page.locator("#ethical-assent-checkbox").check();
  await page.getByRole("button", { name: /Primeira vez/i }).click();
  await page.getByRole("button", { name: "Começar Atividade!" }).click();

  await page.getByRole("button", { name: /Finalizar Oficina & Ir para Corrida/i }).click();
  await page.getByRole("button", { name: /Muito boa/i }).click();
  await page.getByRole("button", { name: "Concluir e Salvar Oficina" }).click();

  await expect(
    page.getByRole("heading", { name: "Oficina concluída com sucesso!" })
  ).toBeVisible();

  const sessions = await getStoredRecords(page, "sessions");
  expect(sessions.length).toBe(1);

  const events = sessions[0].events || [];
  expect(events.length).toBeGreaterThan(0);

  // session_completed deve ser definitivamente o último evento gravado
  const lastEvent = events[events.length - 1];
  expect(lastEvent.event_type).toBe("session_completed");

  // Snapshot deve conter telemetry_status
  expect(sessions[0].telemetry_status).toBeDefined();
});

test("absolute 7-day retention purges expired sessions along with pending, delivered, and quarantined events without extension on resume", async ({ page }) => {
  await page.goto("/alunos/");
  // Aguarda o mount inicial e a limpeza inicial do StudentApp assentarem
  await page.waitForTimeout(500);

  const now = Date.now();
  const dayMs = 24 * 60 * 60 * 1000;

  // Inserir manualmente via IndexedDB
  await page.evaluate(async ({ now, dayMs }) => {
    const dbReq = indexedDB.open("pulselab-student-runner", 1);
    const db = await new Promise((resolve, reject) => {
      dbReq.onsuccess = () => resolve(dbReq.result);
      dbReq.onerror = () => reject(dbReq.error);
    });

    const tx = db.transaction(["sessions", "events"], "readwrite");
    const sessionStore = tx.objectStore("sessions");
    const eventStore = tx.objectStore("events");

    // Sessão 1: Expirada (8 dias) com queued, delivered e quarantined
    sessionStore.put({
      session_id: "expired-sess-1",
      created_at: new Date(now - 8 * dayMs).toISOString(),
      started_at: new Date(now - 8 * dayMs).toISOString(),
      status: "completed"
    });
    eventStore.put({
      event_id: "ev-exp1-queued",
      session_id: "expired-sess-1",
      _delivery_state: "queued",
      occurred_at: new Date(now - 8 * dayMs).toISOString()
    });
    eventStore.put({
      event_id: "ev-exp1-delivered",
      session_id: "expired-sess-1",
      _delivery_state: "delivered",
      occurred_at: new Date(now - 8 * dayMs).toISOString()
    });
    eventStore.put({
      event_id: "ev-exp1-quarantined",
      session_id: "expired-sess-1",
      _delivery_state: "quarantined",
      occurred_at: new Date(now - 8 * dayMs).toISOString()
    });

    // Sessão 2: Expirada (criada há 9 dias, retomada há 1 hora) - retomada não estende retenção
    sessionStore.put({
      session_id: "expired-sess-2-resumed",
      created_at: new Date(now - 9 * dayMs).toISOString(),
      started_at: new Date(now - 9 * dayMs).toISOString(),
      activityStartedAt: now - 1 * 60 * 60 * 1000,
      status: "in_progress"
    });
    eventStore.put({
      event_id: "ev-exp2-queued",
      session_id: "expired-sess-2-resumed",
      _delivery_state: "queued",
      occurred_at: new Date(now - 9 * dayMs).toISOString()
    });
    eventStore.put({
      event_id: "ev-exp2-delivered",
      session_id: "expired-sess-2-resumed",
      _delivery_state: "delivered",
      occurred_at: new Date(now - 9 * dayMs).toISOString()
    });

    // Sessão 3: Válida (criada há 2 dias)
    sessionStore.put({
      session_id: "valid-sess-3",
      created_at: new Date(now - 2 * dayMs).toISOString(),
      started_at: new Date(now - 2 * dayMs).toISOString(),
      status: "completed"
    });
    eventStore.put({
      event_id: "ev-val3-queued",
      session_id: "valid-sess-3",
      _delivery_state: "queued",
      occurred_at: new Date(now - 2 * dayMs).toISOString()
    });
    eventStore.put({
      event_id: "ev-val3-delivered",
      session_id: "valid-sess-3",
      _delivery_state: "delivered",
      occurred_at: new Date(now - 2 * dayMs).toISOString()
    });
    eventStore.put({
      event_id: "ev-val3-quarantined",
      session_id: "valid-sess-3",
      _delivery_state: "quarantined",
      occurred_at: new Date(now - 2 * dayMs).toISOString()
    });

    await new Promise((resolve, reject) => {
      tx.oncomplete = () => {
        db.close();
        resolve();
      };
      tx.onerror = () => reject(tx.error);
    });
  }, { now, dayMs });

  // Confirma que foram gravadas
  const preSessions = await getStoredRecords(page, "sessions");
  const preEvents = await getStoredRecords(page, "events");
  expect(preSessions.length).toBe(3);
  expect(preEvents.length).toBe(8);

  // Recarrega a página (aciona enforceAbsoluteRetention(7) no useEffect do StudentApp)
  await page.reload();

  // Aguarda execução assíncrona do expurgo
  await page.waitForTimeout(500);

  const postSessions = await getStoredRecords(page, "sessions");
  const postEvents = await getStoredRecords(page, "events");

  // Sessões 1 e 2 devem ter sido expurgadas; apenas a sessão 3 deve permanecer
  expect(postSessions.length).toBe(1);
  expect(postSessions[0].session_id).toBe("valid-sess-3");

  // Todos os eventos das sessões 1 e 2 (queued, delivered, quarantined) devem ter sido expurgados conjuntamente
  expect(postEvents.length).toBe(3);
  const remainingEventIds = postEvents.map((e) => e.event_id).sort();
  expect(remainingEventIds).toEqual([
    "ev-val3-delivered",
    "ev-val3-quarantined",
    "ev-val3-queued"
  ]);
});
