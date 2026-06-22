describe("External CI Repo Wizard E2E Tests", () => {
  beforeEach(() => {
    // Login as admin first
    cy.visit("/auth/login");
    cy.get("#session_username").type("admin");
    cy.get(".btn-login").click();
    cy.url().should("eq", Cypress.config().baseUrl + "/");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');

    cy.visit("/admin/config_repos/new");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  afterEach(() => {
    // Clean up eci-test config repos created by this test run.
    // In mock mode the cleanup endpoint may not exist — ignore failures.
    cy.request({ method: "DELETE", url: "/api/admin/config_repos/cleanup", failOnStatusCode: false });
  });

  it("renders step 1 with source type selector", () => {
    // Step label buttons (progress indicator)
    cy.contains("button", "1. Repository").should("exist");
    cy.contains("button", "2. Files").should("exist");

    // Step 1 heading
    cy.contains("h2", "Where is your pipeline?").should("exist");

    // Source type labels
    cy.contains("label", "GitHub Actions").should("exist");
    cy.contains("label", "GitLab CI").should("exist");

    // Repository URL input
    cy.get('input[name="repo_url"]').should("exist");

    // Branch input
    cy.get('input[name="branch"]').should("have.value", "main");

    // Next button
    cy.contains("button", "Find workflow files").should("exist");
  });

  it("toggles source type between GitHub Actions and GitLab CI", () => {
    // Click GitLab CI label
    cy.contains("label", "GitLab CI").click();

    // Verify GitLab CI is now selected (has orange ring)
    cy.contains("label", "GitLab CI")
      .should("have.class", "ring-1");

    // Click back to GitHub Actions
    cy.contains("label", "GitHub Actions").click();
    cy.contains("label", "GitHub Actions")
      .should("have.class", "ring-1");
  });

  it("validates empty repo URL on submit", () => {
    cy.get('input[name="repo_url"]').clear();
    cy.contains("button", "Find workflow files").click();

    // Should show error
    cy.contains("Repository URL is required").should("exist");
  });

  it("validates invalid repo URL format", () => {
    cy.get('input[name="repo_url"]').clear().type("not-a-valid-url");
    cy.contains("button", "Find workflow files").click();

    cy.contains("Must be a valid git URL").should("exist");
  });

  it("proceeds to step 2 with discovered files", () => {
    const repoUrl = "https://github.com/eci-test/step2-test-" + Date.now() + ".git";
    cy.get('input[name="repo_url"]').clear().type(repoUrl);
    cy.contains("button", "Find workflow files").click();

    // Should show step 2
    cy.contains("h2", "Files found in this repository").should("exist");
    cy.contains(".github/workflows/ci.yml").should("exist");
    cy.contains(".github/workflows/deploy.yml").should("exist");
    cy.contains("button", "Select all").should("exist");
    cy.contains("button", "Deselect all").should("exist");
  });

  it("proceeds from step 2 to step 3", () => {
    const repoUrl = "https://github.com/eci-test/st3-test-" + Date.now() + ".git";
    cy.get('input[name="repo_url"]').clear().type(repoUrl);
    cy.contains("button", "Find workflow files").click();
    cy.contains("h2", "Files found in this repository", { timeout: 10000 }).should("exist");

    // Click continue (all files pre-selected)
    cy.contains("button", "Configure 3 files").click();
    cy.contains("h2", "Configure Files", { timeout: 10000 }).should("exist");
  });

  it("proceeds from step 3 to step 4", () => {
    const repoUrl = "https://github.com/eci-test/st4-test-" + Date.now() + ".git";
    cy.get('input[name="repo_url"]').clear().type(repoUrl);
    cy.contains("button", "Find workflow files").click();
    cy.contains("h2", "Files found in this repository", { timeout: 10000 }).should("exist");
    cy.contains("button", "Configure 3 files").click();

    cy.contains("h2", "Configure Files", { timeout: 10000 }).should("exist");
    cy.contains("button", "Translate to GoCD").should("exist");
    cy.contains("button", "Next: Review").click();

    cy.contains("h2", "Review & Save", { timeout: 10000 }).should("exist");
    cy.contains("button", "Save & Finish").should("exist");
  });
});
