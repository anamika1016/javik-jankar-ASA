import "@hotwired/turbo-rails";
import { initPasswordToggles } from "password_toggles";

document.addEventListener("turbo:load", initPasswordToggles);
document.addEventListener("DOMContentLoaded", initPasswordToggles);
if (document.readyState !== "loading") initPasswordToggles();
