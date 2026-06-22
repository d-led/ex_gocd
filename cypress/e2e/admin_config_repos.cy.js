describe("Admin Config Repositories E2E Tests", () => {
  beforeEach(() => {
    cy.visit("/admin/config_repos");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  it("loads config repos page", () => {
    cy.get("body").should("contain.text", "Config");
  });

  it("shows Add Config Repo button linking to wizard", () => {
    cy.get("a[href*='config_repos/new']").should("exist");
  });

  it("page content renders without JS error", () => {
    cy.get("h1, h2, h3, table, .empty").should("exist");
  });
});
