describe("Agents Management", () => {
  beforeEach(() => {
    cy.visitPage("/agents");
  });

  it("loads with toolbar, tabs, and agent selection controls", () => {
    cy.theActiveAgentTabIs("STATIC");
    cy.theElementIsVisible(".bulk-actions");
    cy.thePageShows("DELETE");
    cy.thePageShows("ENABLE");
    cy.thePageShows("DISABLE");
    cy.thePageShows("SCHEDULE TEST JOB");
    // Bulk delete requires confirmation — safety gate
    cy.get("button").contains("DELETE").should("have.attr", "data-confirm");
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
    cy.iSwitchToAgentTab("ELASTIC");
    cy.theActiveAgentTabIs("ELASTIC");
    cy.thePageShows("elastic-agent-k8s-abc123");
    cy.contains("build-agent-01.example.com").should("not.exist");

    // Switch back — static agents return
    cy.iSwitchToAgentTab("STATIC");
    cy.theActiveAgentTabIs("STATIC");
    cy.thePageShows("build-agent-01.example.com");
  });

  it("filters agents via the search box", () => {
    cy.iFilterAgents("build-agent-01");
    cy.get(".agents-table tbody tr").should("exist");
  });

  it("schedules a test job via the toolbar button", () => {
    cy.iClickButton("SCHEDULE TEST JOB");
    cy.theFlashSays("scheduled");
  });
});
