describe("Pipeline Configuration E2E Tests", () => {
  beforeEach(() => {
    // Visit the materials config page for the seeded 'demo' pipeline
    cy.visit("/go/admin/pipelines/demo/edit/materials");
    cy.get('.phx-connected', { timeout: 10000 }).should('exist');
  });

  it("should validate and reject a non-existent pipeline dependency", () => {
    // Click Add Material button
    cy.get("button").contains("Add Material").click();

    // Select "Pipeline Dependency" material type
    cy.get("select[name='type']").select("dependency");

    // Enter a non-existent pipeline name in the Repository URL field
    cy.get("input[name='url']").type("non-existent-pipeline");

    // Submit the configuration form
    cy.get("button").contains("Save Configuration").click();

    // Verify the error message is displayed
    cy.get("[role='alert']").should("contain", "Error: Referenced pipeline 'non-existent-pipeline' does not exist");
  });
});
