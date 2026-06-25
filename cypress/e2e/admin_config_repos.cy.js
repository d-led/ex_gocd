describe("Admin Config Repositories", () => {
  beforeEach(() => {
    cy.loginAsAdmin();
    cy.visitPage("/admin/config_repos");
  });

  it("loads and provides a link to create a new config repo", () => {
    cy.thePageShows("Config");
    cy.thePageHasALinkToAddConfigRepo();
  });
});
