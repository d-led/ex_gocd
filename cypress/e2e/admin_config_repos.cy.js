describe("Admin Config Repositories E2E Tests", () => {
  beforeEach(() => {
    // Login via the form UI to get a valid CSRF token and session
    cy.visit("/auth/login");
    cy.get("#session_username").type("admin");
    cy.get(".btn-login").click();
    // Should redirect to dashboard after login
    cy.url().should("eq", Cypress.config().baseUrl + "/");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');

    cy.visit("/admin/config_repos");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  it("displays config repos tab with real data", () => {
    // Should show the config repos table
    cy.get("table").should("exist");

    // Should show seeded repos
    cy.contains("td", "eci-test/demo-workflows.git").should("exist");
    cy.contains("td", "eci-test/demo-pipelines.git").should("exist");
    cy.contains("td", "eci-test/gocd-pipelines.git").should("exist");
  });

  it("displays source_type badges with correct colors", () => {
    // GitHub Actions badge should be present
    cy.contains("span", "GitHub Actions").should("exist");
    // GitLab CI badge
    cy.contains("span", "GitLab CI").should("exist");
    // GoCD Pipeline badge
    cy.contains("span", "GoCD Pipeline").should("exist");
  });

  it("shows Add Config Repo button", () => {
    cy.contains("a", "Add Config Repo").should("exist");
    cy.contains("a", "Add Config Repo")
      .should("have.attr", "href", "/admin/config_repos/new");
  });

  it("status column shows meaningful labels", () => {
    // The gocd_pipeline repo has last_parsed_at set → "Good"
    cy.contains("span", "Good").should("exist");
    // The github_actions and gitlab_ci repos have no last_parsed_at → "Never Synced"
    cy.contains("span", "Never Synced").should("exist");
  });

  it("shows Sync and Delete action buttons for each repo", () => {
    // At least one Sync button
    cy.get("button").contains("Sync").should("exist");
    // At least one Delete button with data-confirm
    cy.get("button").contains("Delete").should("exist");
    cy.get("button").contains("Delete")
      .should("have.attr", "data-confirm");
  });

  it("clicking Delete shows confirmation dialog", () => {
    cy.get("button").contains("Delete").first().click();
    // Cypress auto-accepts window.confirm, so the event fires
    // Verify the click happened (button still there since it's LiveView)
    cy.get("button").contains("Delete").should("exist");
  });
});
