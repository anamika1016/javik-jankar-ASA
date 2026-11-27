// Warm the alternate dashboard views first, sequentially and while idle.
// HTML stays on the server; every actual click still checks current source data.
let generation = 0;
let controller;
const warmedNavigations = new WeakSet();
let pendingModeLink = null;

const clearPendingMode = () => {
  if (!pendingModeLink?.isConnected) {
    pendingModeLink = null;
    return;
  }
  pendingModeLink.removeAttribute("aria-busy");
  pendingModeLink.classList.remove("is-loading");
  const label = pendingModeLink.querySelector("[data-dashboard-mode-label]");
  if (label?.dataset.originalLabel) {
    label.textContent = label.dataset.originalLabel;
    delete label.dataset.originalLabel;
  }
  pendingModeLink = null;
};

const warmDashboardModes = () => {
  const navigation = document.querySelector(".dashboard-view-switch");
  if (!navigation || warmedNavigations.has(navigation)) return;
  const current = ++generation;
  controller?.abort();
  controller = new AbortController();
  const { signal } = controller;
  if (document.visibilityState === "hidden" || navigator.connection?.saveData) return;
  const links = [...document.querySelectorAll("[data-dashboard-mode-link]")]
    .sort((a, b) => Number(a.getAttribute("aria-current") === "page") - Number(b.getAttribute("aria-current") === "page"));
  if (!links.length) return;
  warmedNavigations.add(navigation);
  const run = async () => {
    for (const link of links) {
      if (current !== generation || document.visibilityState === "hidden") return;
      const url = new URL(link.href, window.location.href);
      if (url.origin !== window.location.origin) continue;
      try {
        await fetch(url.href, {
          credentials: "same-origin", cache: "no-store", signal,
          headers: { Accept: "text/html", "X-Dashboard-Warm": "1" }
        });
      } catch (_) {
        // Warming is optional; the normal link always remains usable.
        return;
      }
    }
  };
  if (window.requestIdleCallback) window.requestIdleCallback(run, { timeout: 1000 });
  else setTimeout(run, 150);
};

document.addEventListener("turbo:load", () => {
  clearPendingMode();
  warmDashboardModes();
});
document.addEventListener("turbo:before-visit", (event) => {
  generation++;
  controller?.abort();
  const url = new URL(event.detail.url, window.location.href);
  const link = [...document.querySelectorAll("[data-dashboard-mode-link]")]
    .find((candidate) => candidate.href === url.href);
  if (!link) return;

  clearPendingMode();
  pendingModeLink = link;
  link.setAttribute("aria-busy", "true");
  link.classList.add("is-loading");
  const label = link.querySelector("[data-dashboard-mode-label]");
  if (label) {
    label.dataset.originalLabel = label.textContent;
    label.textContent = "Loading…";
  }
});
document.addEventListener("turbo:submit-start", () => { generation++; controller?.abort(); });
document.addEventListener("turbo:fetch-request-error", () => {
  const link = pendingModeLink;
  if (!link) return;
  clearPendingMode();
  const message = document.createElement("div");
  message.className = "dashboard-navigation-error";
  message.setAttribute("role", "alert");
  message.textContent = "Dashboard load nahi hua. Internet check karke dobara click karein.";
  document.querySelector(".dashboard-page")?.prepend(message);
});

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", warmDashboardModes);
else warmDashboardModes();
