describe("Agents Management", () => {
  beforeEach(() => {
    cy.visitPage("/agents");
  });

  it("loads with toolbar, tabs, and agent selection controls", () => {
    cy.theActiveAgentTabIs("STATIC");
    cy.theBulkActionsToolbarIsVisible();
    cy.thePageShows("DELETE");
    cy.thePageShows("ENABLE");
    cy.thePageShows("DISABLE");
    cy.thePageShows("SCHEDULE TEST JOB");
    // Bulk delete requires confirmation — safety gate
    cy.theDeleteButtonRequiresConfirmation();
  });

  it("displays agent count statistics", () => {
    cy.thePageShows("Total");
    cy.thePageShows("Enabled");
    cy.thePageShows("Disabled");
  });

  it("shows static agents on the STATIC tab and elastic agents on the ELASTIC tab", () => {
    // Static tab shows build agents
    cy.thePageShows("build-agent-01.example.com");
    cy.thePageShows("build-agent-02.example.com");

    // Elastic tab shows the Kubernetes elastic agent, static agents disappear
    cy.switchToAgentTab("ELASTIC");
    cy.theActiveAgentTabIs("ELASTIC");
    cy.thePageShows("elastic-agent-k8s-abc123");
    cy.thePageDoesNotShow("build-agent-01.example.com");

    // Switch back — static agents return
    cy.switchToAgentTab("STATIC");
    cy.theActiveAgentTabIs("STATIC");
    cy.thePageShows("build-agent-01.example.com");
  });

  it("filters agents via the search box", () => {
    cy.filterAgents("build-agent-01");
    cy.theAgentTableIsNotEmpty();
  });

  it("schedules a test job via the toolbar button", () => {
    cy.scheduleTestJob();
    cy.theFlashSays("scheduled");
  });
});
