describe("Admin Config Repositories", () => {
  beforeEach(() => {
    cy.visitPage("/admin/config_repos");
  });

  it("loads and provides a link to create a new config repo", () => {
    cy.thePageShows("Config");
    cy.get("a[href*='config_repos/new']").should("exist");
  });
});
