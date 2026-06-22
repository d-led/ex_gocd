describe("Materials Page", () => {
  beforeEach(() => {
    cy.visitPage("/materials");
  });

  it("loads the materials page", () => {
    cy.theMaterialsPageIsLoaded();
    cy.thePageShows("Materials");
  });

  it("displays material cards with SCM type, auto-update status, and branch when expanded", () => {
    const fp = "8d78bc9f6c661806";
    cy.theMaterialIsVisible("https://github.com/gocd/docs.git");
    cy.theMaterialScmTypeIs(fp, "git");
    cy.iExpandMaterial(fp);
    cy.theMaterialAutoUpdateIs(fp, "Active (polling)");
    cy.theMaterialBranchIs(fp, "master");
  });

  it("filters the materials list via the search bar", () => {
    cy.iSearchMaterials("docs.git");
    cy.theMaterialIsVisible("https://github.com/gocd/docs.git");
    cy.theMaterialIsNotVisible("https://github.com/gocd/gocd.git");

    cy.iSearchMaterials("nonexistent-scm-repo");
    cy.thePageShows("No materials found");
  });

  it("navigates from Usages modal pipeline link to dashboard with search pre-filled", () => {
    const fp = "f828d66cdfa6d522";

    cy.iOpenUsagesModal(fp);
    cy.theUsagesModalContains("docs-build");
    cy.iClickUsagesModalPipelineLink("docs-build");

    cy.theUrlContains("/pipelines?search=docs-build");
    cy.theDashboardShows("docs-build");
    cy.theDashboardDoesNotShow("build-linux");
  });

  it("opens Modifications modal, shows history, filters, and closes", () => {
    const fp = "8d78bc9f6c661806";

    cy.iOpenModificationsModal(fp);
    cy.theModificationsModalContains("upgrade actions and fix compilation warnings");

    cy.iSearchModifications("upgrade");
    cy.theModificationsModalContains("upgrade actions");

    cy.iCloseModificationsModal();
  });
});
