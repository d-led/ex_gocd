describe("Pipeline Configuration", () => {
  beforeEach(() => {
    cy.loginAsAdmin();
    cy.visitPage("/go/admin/pipelines/demo/edit/materials");
  });

  it("validates and rejects a non-existent pipeline dependency", () => {
    cy.addMaterial();
    cy.selectMaterialType("dependency");
    cy.validateWithNonexistentPipelineDependency();
  });
});
