// Materials Page tests.
// Covers ruby spec: materials_spa_spec.rb

describe("Materials Page", () => {
  beforeEach(() => {
    cy.visitPage("/materials");
    cy.theMaterialsPageIsLoaded();
  });

  it("has a search bar for filtering materials", () => {
    cy.theMaterialsPageHasSearch();
  });

  it("can search materials and still renders the page", () => {
    cy.searchMaterials("nonexistent-scm-repo");
    cy.theMaterialsPageIsLoaded();
  });

  it("displays materials or renders without errors", () => {
    cy.theMaterialsPageIsLoaded();
  });
});
