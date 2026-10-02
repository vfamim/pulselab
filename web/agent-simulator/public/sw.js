const CACHE_PREFIX = "pulselab-test-v2-";
const CACHE_NAME = CACHE_PREFIX + "2.0.0-test.1";
const SHELL = [
  "/alunos/",
  "/alunos/index.html",
  "/alunos/manifest.webmanifest",
  "/alunos/icon.svg",
  "/alunos/robot.png",
];
self.addEventListener("install", (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      await cache.addAll(SHELL);
      const response = await fetch("/alunos/index.html", { cache: "reload" });
      const html = await response.text();
      const assets = [...html.matchAll(/(?:src|href)="([^"]+)"/g)]
        .map((m) => m[1])
        .filter((p) => p.startsWith("/alunos/assets/"));
      await cache.addAll(assets);
      await self.skipWaiting();
    })(),
  );
});
self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((k) => k.startsWith(CACHE_PREFIX) && k !== CACHE_NAME)
          .map((k) => caches.delete(k)),
      );
      await self.clients.claim();
    })(),
  );
});
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (
    event.request.method !== "GET" ||
    url.origin !== self.location.origin ||
    !url.pathname.startsWith("/alunos/")
  )
    return;
  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      if (event.request.mode === "navigate") {
        try {
          return await fetch(event.request);
        } catch {
          return await cache.match("/alunos/index.html");
        }
      }
      // Only same-origin static files are cached. Dev servers may add Vary: Origin;
      // module/style requests use CORS while install-time requests do not.
      return (
        (await cache.match(event.request, { ignoreVary: true })) ||
        fetch(event.request)
      );
    })(),
  );
});
