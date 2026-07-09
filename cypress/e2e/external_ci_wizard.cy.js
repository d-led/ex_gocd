describe("External CI Repo Wizard E2E Tests", () => {
  beforeEach(() => {
    cy.loginAsAdmin();
    cy.visit("/admin/config_repos/new");
    cy.get(".phx-connected", { timeout: 10000 }).should("exist");
  });

  afterEach(() => {
    // Clean up eci-test config repos created by this test run.
    // In mock mode the cleanup endpoint may not exist — ignore failures.
    cy.request({
      method: "DELETE",
      url: "/api/admin/config_repos/cleanup",
      failOnStatusCode: false,
    });
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
    cy.contains("label", "GitLab CI").should("have.class", "ring-1");

    // Click back to GitHub Actions
    cy.contains("label", "GitHub Actions").click();
    cy.contains("label", "GitHub Actions").should("have.class", "ring-1");
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

  it("step 2 and beyond require GitHub API — skipped in mock mode", function () {
    // The file-discovery steps (2-4) require live GitHub API access.
    // In mock mode or offline, the server cannot reach GitHub to discover
    // workflow files, so we verify only that step 1 renders correctly
    // (tested above) and that the wizard form is functional.
    cy.log(
      "File discovery (steps 2-4) requires GitHub API — not tested in mock mode",
    );
  });
});
