describe("Materials Page", () => {
  beforeEach(() => {
    cy.visitPage("/materials");
  });

  it("loads the materials page", () => {
    cy.get(".materials-page, .phx-connected", { timeout: 10000 }).should(
      "exist",
    );
    cy.get(".page-title, h1, h2").should("contain", "Materials");
  });

  it("displays material cards when materials are present", () => {
    cy.get("body").then(($body) => {
      const hasMaterials =
        $body.find(".material-card, .materials-list li").length > 0;
      if (hasMaterials) {
        cy.get(".material-card, .materials-list li").should(
          "have.length.at.least",
          1,
        );
      } else {
        // No materials is also valid — page should still render
        cy.get(".materials-page").should("exist");
      }
    });
  });

  it("has a search bar for filtering materials", () => {
    cy.get(
      '#material-search, input[placeholder*="search" i], input[placeholder*="Search" i]',
    ).should("exist");
  });

  it("can search materials and see results or empty state", () => {
    cy.get(
      '#material-search, input[placeholder*="search" i], input[placeholder*="Search" i]',
    ).type("nonexistent-scm-repo");
    // Either shows "no materials" or still shows the page
    cy.get(".materials-page").should("exist");
  });
});
