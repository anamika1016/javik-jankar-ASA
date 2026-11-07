const initPasswordToggles = () => {
  document.querySelectorAll("[data-password-toggle]").forEach((button) => {
    if (button.dataset.passwordToggleBound === "true") return;

    button.dataset.passwordToggleBound = "true";
    button.addEventListener("click", () => {
      const input = button.closest(".password-field, .login-password-field")?.querySelector("[data-password-toggle-input]");
      if (!input) return;

      const showPassword = input.type === "password";
      input.type = showPassword ? "text" : "password";
      button.setAttribute("aria-label", showPassword ? "Hide password" : "Show password");
      button.title = showPassword ? "Hide password" : "Show password";
      button.classList.toggle("is-visible", showPassword);
    });
  });
};

export { initPasswordToggles };
