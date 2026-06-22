describe("Pipeline Configuration", () => {
  beforeEach(() => {
    cy.visitPage("/go/admin/pipelines/demo/edit/materials");
  });

  it("validates and rejects a non-existent pipeline dependency", () => {
    cy.iAddMaterial();
    cy.iSelectMaterialType("dependency");
    cy.iTypeInto("url", "non-existent-pipeline");
    cy.iSaveConfiguration();
    cy.theErrorSays("Error: Referenced pipeline 'non-existent-pipeline' does not exist");
  });
});
