import { Turbo } from "@hotwired/turbo-rails";

const markNavigationPending = () => {
  document.documentElement.removeAttribute("data-navigation-complete");
};

const clearCompletedNavigationProgress = () => {
  if (document.documentElement.hasAttribute("data-turbo-preview")) return;

  // Removing the DOM bar alone leaves Turbo's delayed show timers alive.
  // Stop the indicator lifecycle without stopping the visit or its requests.
  const adapter = Turbo.session?.adapter;
  adapter?.hideVisitProgressBar?.();
  adapter?.hideFormProgressBar?.();
  document.documentElement.setAttribute("data-navigation-complete", "true");
  document.querySelectorAll(".turbo-progress-bar").forEach((bar) => bar.remove());
};

const clearProgressWhenIdle = () => {
  const state = Turbo.navigator?.currentVisit?.state;
  if (state !== "initialized" && state !== "started") clearCompletedNavigationProgress();
};

document.addEventListener("turbo:visit", markNavigationPending);
document.addEventListener("turbo:submit-start", markNavigationPending);
document.addEventListener("turbo:render", clearCompletedNavigationProgress);
document.addEventListener("turbo:load", clearProgressWhenIdle);
document.addEventListener("turbo:submit-end", () => {
  // Stream/validation responses can finish without a full-page render. A
  // redirect's new visit must keep its loading indicator until it renders.
  clearProgressWhenIdle();
});
document.addEventListener("DOMContentLoaded", clearProgressWhenIdle);
window.addEventListener("pageshow", (event) => {
  if (event?.persisted) clearCompletedNavigationProgress();
  else clearProgressWhenIdle();
});

if (document.readyState !== "loading") clearProgressWhenIdle();
