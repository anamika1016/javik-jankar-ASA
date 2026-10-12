// Dashboard list exports follow the visible search while exporting every matching page.
const bindDashboardReportExports = () => {
  document.querySelectorAll("[data-dashboard-report]").forEach((report) => {
    const search = report.querySelector("input[data-table-search]");
    if (!search || search.dataset.dashboardExportBound === "true") return;
    search.dataset.dashboardExportBound = "true";
    const update = () => report.querySelectorAll("a[data-report-export]").forEach((link) => {
      const url = new URL(link.href, window.location.origin);
      if (search.value.trim()) url.searchParams.set("q", search.value.trim());
      else url.searchParams.delete("q");
      link.href = url.toString();
    });
    search.addEventListener("input", update);
    update();
  });
};

document.addEventListener("turbo:load", bindDashboardReportExports);
bindDashboardReportExports();
