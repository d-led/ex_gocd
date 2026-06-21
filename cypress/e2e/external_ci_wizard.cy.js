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

  it("renders step 1 with source type selector", () => {
    // Progress indicator visible
    cy.get(".h-2.rounded-full").should("have.length", 4);

    // Step 1 heading
    cy.contains("h2", "Repository Details").should("exist");

    // Source type buttons
    cy.contains("button", "GitHub Actions").should("exist");
    cy.contains("button", "GitLab CI").should("exist");

    // Repository URL input
    cy.get('input[name="repo_url"]').should("exist");

    // Branch input
    cy.get('input[name="branch"]').should("have.value", "main");

    // Next button
    cy.contains("button", "Next: Discover Files").should("exist");
  });

  it("toggles source type between GitHub Actions and GitLab CI", () => {
    // Click GitLab CI
    cy.contains("button", "GitLab CI").click();

    // Verify GitLab CI is now selected (has orange border)
    cy.contains("button", "GitLab CI")
      .should("have.class", "border-orange-300");

    // Click back to GitHub Actions
    cy.contains("button", "GitHub Actions").click();
    cy.contains("button", "GitHub Actions")
      .should("have.class", "border-purple-300");
  });

  it("validates empty repo URL on submit", () => {
    cy.get('input[name="repo_url"]').clear();
    cy.contains("button", "Next: Discover Files").click();

    // Should show error
    cy.contains("Repository URL is required").should("exist");
  });

  it("validates invalid repo URL format", () => {
    cy.get('input[name="repo_url"]').clear().type("not-a-valid-url");
    cy.contains("button", "Next: Discover Files").click();

    cy.contains("Must be a valid git URL").should("exist");
  });

  it("proceeds to step 2 with discovered files", () => {
    const repoUrl = "https://github.com/eci-test/step2-test-" + Date.now() + ".git";
    cy.get('input[name="repo_url"]').clear().type(repoUrl);
    cy.contains("button", "Next: Discover Files").click();

    // Should show step 2 heading
    cy.contains("h2", "Discovered Workflow Files").should("exist");

    // Should show discovered files
    cy.contains(".github/workflows/ci.yml").should("exist");
    cy.contains(".github/workflows/deploy.yml").should("exist");
    cy.contains(".github/workflows/nightly.yml").should("exist");

    // Back button
    cy.contains("button", "Back").should("exist");
    // Next button
    cy.contains("button", "Next: Configure Files").should("exist");
  });

  it("proceeds through full wizard flow", () => {
    const repoUrl = "https://github.com/eci-test/wizard-test-" + Date.now() + ".git";

    // Step 1
    cy.get('input[name="repo_url"]').clear().type(repoUrl);
    cy.contains("button", "Next: Discover Files").click();

    // Wait for step 2 to fully render
    cy.contains("h2", "Discovered Workflow Files", { timeout: 10000 }).should("exist");
    cy.get("input[type='checkbox']").should("have.length.greaterThan", 0);

    // Click all checkboxes to ensure they're checked (Cypress might not honor the checked attribute)
    cy.get("input[type='checkbox']").each(($el) => {
      cy.wrap($el).check({ force: true });
    });

    // Click next to go to step 3
    cy.contains("button", "Next: Configure Files").click();

    // Should show step 3
    cy.contains("h2", "Configure Files", { timeout: 10000 }).should("exist");
    cy.contains("button", "Translate to GoCD").should("exist");

    // Proceed to review
    cy.contains("button", "Next: Review").click();

    // Step 4
    cy.contains("h2", "Review & Save", { timeout: 10000 }).should("exist");
    cy.contains("button", "Save & Finish").should("exist");
  });
});
