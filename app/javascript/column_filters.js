// Column filter popovers in a list table's heading row.
//
// Each heading carries a toggle, and the panel behind it holds the comparison
// dropdown and the value box. Both controls belong to the page's search form
// through their `form` attribute, so submitting sends every column's filter at
// once and the server does the filtering -- the list is paged, so filtering the
// rendered rows would only ever see the page on screen.

const closeAll = (except) => {
  document.querySelectorAll("[data-column-filter-popover]").forEach((panel) => {
    if (panel === except) return;
    panel.hidden = true;
    panel.closest("th")?.querySelector("[data-column-filter-toggle]")
      ?.setAttribute("aria-expanded", "false");
  });
};

const bindColumnFilters = () => {
  document.querySelectorAll("[data-column-filter-toggle]").forEach((toggle) => {
    if (toggle.dataset.columnFilterBound === "true") return;
    toggle.dataset.columnFilterBound = "true";

    toggle.addEventListener("click", (event) => {
      event.stopPropagation();
      const panel = toggle.closest("th")?.querySelector("[data-column-filter-popover]");
      if (!panel) return;
      const opening = panel.hidden;
      closeAll(opening ? panel : null);
      panel.hidden = !opening;
      toggle.setAttribute("aria-expanded", String(opening));
      if (opening) panel.querySelector(".column-filter-value")?.focus();
    });
  });

  // Clearing empties this column only, then submits so the row count matches
  // what the header now shows.
  document.querySelectorAll("[data-column-filter-clear]").forEach((button) => {
    if (button.dataset.columnFilterBound === "true") return;
    button.dataset.columnFilterBound = "true";

    button.addEventListener("click", () => {
      const panel = button.closest("[data-column-filter-popover]");
      const value = panel?.querySelector(".column-filter-value");
      const operator = panel?.querySelector(".column-filter-operator");
      if (value) value.value = "";
      if (operator) operator.selectedIndex = 0;
      document.getElementById("afl-list-search")?.requestSubmit();
    });
  });

  // "Is empty" and "Is not empty" ask about the column itself, so the value
  // box has nothing to contribute.
  document.querySelectorAll("[data-column-filter-operator]").forEach((operator) => {
    if (operator.dataset.columnFilterBound === "true") return;
    operator.dataset.columnFilterBound = "true";

    const syncValueBox = () => {
      const value = operator.closest("[data-column-filter-popover]")?.querySelector(".column-filter-value");
      if (!value) return;
      const valueless = operator.value === "empty" || operator.value === "not_empty";
      value.disabled = valueless;
      if (valueless) value.value = "";
    };
    operator.addEventListener("change", syncValueBox);
    syncValueBox();
  });
};

// Columns nobody filtered have nothing to say. Left enabled they still post
// an empty value and a default comparison each, so one filter produced a query
// string carrying all twenty-one -- unreadable, unshareable, and hard to tell
// at a glance what is actually filtering. Disabled controls are not submitted;
// they are re-enabled immediately so the form stays usable if the visit fails.
const dropUnusedColumnFilters = (form) => {
  const disabled = [];
  // Searched from the document, not the form: these controls sit in the table
  // head and join the form through their `form` attribute, so they are not
  // descendants of it.
  document.querySelectorAll(`.column-filter-value[form="${form.id}"]`).forEach((value) => {
    const panel = value.closest("[data-column-filter-popover]");
    const operator = panel?.querySelector(".column-filter-operator");
    const valueless = operator && (operator.value === "empty" || operator.value === "not_empty");
    if (value.value.trim() !== "" || valueless) return;

    [value, operator].forEach((field) => {
      if (!field || field.disabled) return;
      field.disabled = true;
      disabled.push(field);
    });
  });
  setTimeout(() => disabled.forEach((field) => { field.disabled = false; }), 0);
};

document.addEventListener("submit", (event) => {
  if (event.target?.id === "afl-list-search") dropUnusedColumnFilters(event.target);
}, true);

// A click anywhere else closes the open panel; Escape does too.
document.addEventListener("click", (event) => {
  if (event.target.closest("[data-column-filter-popover], [data-column-filter-toggle]")) return;
  closeAll(null);
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeAll(null);
});

document.addEventListener("turbo:load", bindColumnFilters);
document.addEventListener("DOMContentLoaded", bindColumnFilters);
bindColumnFilters();
