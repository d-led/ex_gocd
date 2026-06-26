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
    cy.get(".site-header", { timeout: 10000 }).should("be.visible");
    cy.get(".site-navigation_left a").contains("Dashboard").should("exist");
    cy.get(".site-navigation_left a").contains("Agents").should("exist");
    cy.get(".site-navigation_left a").contains("Materials").should("exist");
    cy.get(".site-navigation_left a").contains("Admin").should("exist");
  });

  it("dashboard search input is functional", () => {
    cy.visitPage("/pipelines");

    // Search input should exist and accept typing
    cy.get("#pipeline-search").should("be.visible").type("z");

    // Page should still be alive after typing
    cy.get(".dashboard", { timeout: 5000 }).should("exist");
  });

  it("navigates between pages without errors", () => {
    cy.visitPage("/pipelines");

    // Click Agents nav link
    cy.get(".site-navigation_left a").contains("Agents").click();
    cy.visitPage("/agents");

    // Click Materials nav link
    cy.get(".site-navigation_left a").contains("Materials").click();
    cy.visitPage("/materials");

    // Click back to Dashboard
    cy.get(".site-navigation_left a").contains("Dashboard").click();
    cy.visitPage("/pipelines");
  });
});
