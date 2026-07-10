// Smoke test: verifies the app boots and key pages render without errors.
// Runs first (01_ prefix) to fail fast if the server is fundamentally broken.
// Does NOT assert on specific pipeline data — only that UI infrastructure works.

describe("Smoke Test — App Health", () => {
  const pages = [
    { path: "/pipelines", name: "Dashboard", sign: ".dashboard" },
    { path: "/agents", name: "Agents", sign: ".agents-page" },
    { path: "/materials", name: "Materials", sign: ".materials-page" },
  ];

  pages.forEach(({ path, name, sign }) => {
    it(`${name} page loads and renders`, () => {
      cy.visitPage(path);
      cy.get(sign, { timeout: 10000 }).should("exist");
    });
  });

  it("Admin page loads and renders", () => {
    cy.loginAsAdmin();
    cy.visitPage("/admin");
    cy.get(".admin-page-wrapper", { timeout: 10000 }).should("exist");
  });

  it("header navigation links are present", () => {
    cy.loginAsAdmin();
    cy.visitPage("/pipelines");
    ["Dashboard", "Agents", "Materials", "Admin"].forEach((label) => {
      cy.theHeaderHasNavLink(label);
    });
  });

  it("dashboard search input accepts text", () => {
    cy.visitPage("/pipelines");
    cy.theSearchInputAcceptsText();
  });

  it("navigates between pages without errors", () => {
    cy.visitPage("/pipelines");
    cy.goToAgents();
    cy.visitPage("/materials");
    cy.goToDashboard();
  });
});
