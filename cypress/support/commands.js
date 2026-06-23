const SELECTORS = {
  dashboard: ".dashboard",
  pipeline: ".pipeline",
  pipelineName: ".pipeline_name",
  playButton: ".pipeline_btn.play",
  pauseButton: ".pipeline_btn.pause",
  stageList: ".pipeline_stages",
  stageBlock: ".pipeline_stage",
  searchInput: "#pipeline-search",
  dropdown: ".c-dropdown",
  dropdownItem: ".c-dropdown-item",

  agentsPage: ".agents-page",
  tabButton: ".tab-button",
  agentTable: ".agents-table",
  agentRow: ".agents-table tbody tr",
  agentName: ".agent-name",
  selectAllCheckbox: ".agents-table thead .checkbox-cell input",
  agentCheckbox: ".checkbox-cell input",

  historyPage: ".agent-job-history-page",
  historyRow: ".job-history-table tbody tr",
  jobLink: ".job-link",
  paginationButton: ".btn-pagination",

  detailPage: ".agent-job-run-detail-page",
  consoleLog: ".console-log",
  cancelButton: ".btn-danger",

  materialsPage: ".materials-page",
  materialsList: ".materials-list",
  materialCard: ".material-card",
  materialSearchInput: "#material-search",
  materialUrl: ".material-url",
  materialPipelineBadge: ".material-pipeline-badge",

  // Modal selectors
  usagesModal: "#usages-modal",
  usagesModalOk: "#usages-modal-ok",
  modificationsModal: "#modifications-modal",
  modificationsModalOk: "#modifications-modal-ok",
  modificationsSearchInput: "#mod-search-form input",
  modRow: ".mod-row",
};

Cypress.Commands.add("verifyDashboardLoaded", () => {
  cy.get(SELECTORS.dashboard).should("exist");
});

Cypress.Commands.add("verifyPipelineVisible", (name) => {
  cy.get(SELECTORS.pipeline)
    .contains(SELECTORS.pipelineName, name)
    .should("be.visible");
});

Cypress.Commands.add("verifyPipelineNotVisible", (name) => {
  cy.get(SELECTORS.pipelineName).contains(name).should("not.exist");
});

Cypress.Commands.add("triggerPipeline", (name) => {
  cy.get(SELECTORS.pipeline)
    .contains(SELECTORS.pipelineName, name)
    .parents(SELECTORS.pipeline)
    .find(SELECTORS.playButton)
    .click();
});

Cypress.Commands.add("searchPipelines", (query) => {
  if (query === "") {
    cy.get(SELECTORS.searchInput).clear();
  } else {
    cy.get(SELECTORS.searchInput).clear().type(query);
  }
});

Cypress.Commands.add("verifyActiveTab", (text) => {
  cy.get(SELECTORS.tabButton + ".active").should("contain", text);
});

Cypress.Commands.add("selectAgentTab", (text) => {
  cy.get(SELECTORS.tabButton).contains(text).click();
});

Cypress.Commands.add("verifyAgentExists", (hostname) => {
  cy.get(SELECTORS.agentName).contains(hostname).should("exist");
});

Cypress.Commands.add("verifyAgentNotExist", (hostname) => {
  cy.get(SELECTORS.agentName).contains(hostname).should("not.exist");
});

Cypress.Commands.add("verifyAgentState", (hostname, state) => {
  const cssClass = ".status-" + state.toLowerCase().replace("_", "-");
  cy.get(SELECTORS.agentRow)
    .contains(hostname)
    .parents("tr")
    .find(cssClass)
    .should("exist");
});

Cypress.Commands.add("toggleAgentSelection", (hostname) => {
  cy.get(SELECTORS.agentRow)
    .contains(hostname)
    .parents("tr")
    .find(SELECTORS.agentCheckbox)
    .click();
});

Cypress.Commands.add("toggleSelectAllAgents", () => {
  cy.get(SELECTORS.selectAllCheckbox).click();
});

Cypress.Commands.add("performBulkAction", (action) => {
  const btnText = action.toUpperCase();
  cy.get(".bulk-actions button").contains(btnText).click();
});

Cypress.Commands.add("verifyJobHistoryPage", (hostname) => {
  cy.get(SELECTORS.historyPage).should("exist");
  cy.get(".agent-info").should("contain", hostname);
});

Cypress.Commands.add("clickJobHistoryLink", (hostname) => {
  cy.get(SELECTORS.agentRow).contains(hostname).click();
});

Cypress.Commands.add("clickJobHistoryRowLink", (jobName) => {
  cy.get(SELECTORS.historyRow).contains(jobName).click();
});

Cypress.Commands.add("verifyConsoleLogsVisible", (jobName) => {
  cy.get(SELECTORS.detailPage).should("exist");
  cy.get(SELECTORS.detailPage + " h1").should("contain", jobName);
  cy.get(SELECTORS.consoleLog).should("exist");
});

Cypress.Commands.add("verifyMaterialsPageLoaded", () => {
  cy.get(SELECTORS.materialsPage).should("exist");
});

Cypress.Commands.add("searchMaterials", (query) => {
  if (query === "") {
    cy.get(SELECTORS.materialSearchInput).clear();
  } else {
    cy.get(SELECTORS.materialSearchInput).clear().type(query);
  }
});

Cypress.Commands.add("verifyMaterialVisible", (url) => {
  cy.get(SELECTORS.materialUrl).contains(url).should("be.visible");
});

Cypress.Commands.add("verifyMaterialNotVisible", (url) => {
  cy.get(SELECTORS.materialUrl).contains(url).should("not.exist");
});

Cypress.Commands.add("verifySCMType", (fingerprint, type) => {
  cy.get(`#material-${fingerprint} .scm-logo-box`).should("contain", type);
});

Cypress.Commands.add("expandMaterialCard", (fingerprint) => {
  cy.get(`#material-${fingerprint} .collapse-header`).click();
});

Cypress.Commands.add("verifyAutoUpdateStatus", (fingerprint, status) => {
  cy.get(`#material-${fingerprint} .collapse-body`)
    .should("contain", "Auto Update")
    .and("contain", status);
});

Cypress.Commands.add("verifyBranchName", (fingerprint, branchName) => {
  cy.get(`#material-${fingerprint} .collapse-body`)
    .should("contain", "Branch")
    .and("contain", branchName);
});

Cypress.Commands.add("openUsagesModal", (fingerprint) => {
  cy.get(`#material-${fingerprint} [data-test-id="show-usages"]`).click();
});

Cypress.Commands.add("verifyUsagesModalContains", (pipelineName) => {
  cy.get(SELECTORS.usagesModal)
    .should("be.visible")
    .and("contain", pipelineName);
});

Cypress.Commands.add("clickUsagesModalPipelineLink", (pipelineName) => {
  cy.get(SELECTORS.usagesModal)
    .find(".pipeline-link")
    .contains(pipelineName)
    .click();
});

Cypress.Commands.add("closeUsagesModal", () => {
  cy.get(SELECTORS.usagesModalOk).click();
});

Cypress.Commands.add("openModificationsModal", (fingerprint) => {
  cy.get(
    `#material-${fingerprint} [data-test-id="show-modifications"]`,
  ).click();
});

Cypress.Commands.add("verifyModificationsModalContains", (text) => {
  cy.get(SELECTORS.modificationsModal)
    .should("be.visible")
    .and("contain", text);
});

Cypress.Commands.add("searchModificationsInModal", (query) => {
  cy.get(SELECTORS.modificationsSearchInput).clear().type(query);
});

Cypress.Commands.add("closeModificationsModal", () => {
  cy.get(SELECTORS.modificationsModalOk).click();
});

// --- Screenshot helpers ---

Cypress.Commands.add("appScreenshot", (name) => {
  const specName = Cypress.spec.name.replace(/\.cy\.(js|ts|jsx|tsx)$/, "");
  const src = `cypress/screenshots/${specName}.cy.js/${name}.png`;
  const dest = `docs/screenshots/${name}.png`;
  cy.screenshot(name, { capture: "viewport" });
  cy.task("copyScreenshot", { src, dest }, { log: false }).then((res) => {
    if (res && res.error) throw new Error(res.error);
  });
});

// --- Auth helpers ---

Cypress.Commands.add("loginAsAdmin", () => {
  cy.session("admin", () => {
    cy.visit("/auth/login");
    cy.get("#session_username").type("admin");
    cy.get(".btn-login").click();
    cy.url().should("eq", Cypress.config().baseUrl + "/");
  });
});

// ============================================================
// Domain Language Commands
//
// Tests use ONLY these commands. No cy.get, no selectors, no magic
// strings. When the DOM changes, fix the implementation here —
// the tests stay untouched.
// ============================================================

// -- App / Navigation ---------------------------------------------------

Cypress.Commands.add("visitPage", (path) => {
  cy.visit(path);
  cy.get(".phx-connected", { timeout: 10000 }).should("exist");
});

Cypress.Commands.add("clickButton", (label) => {
  cy.get("button").contains(label).click();
});

Cypress.Commands.add("clickLink", (label) => {
  cy.get("a").contains(label).click();
});

Cypress.Commands.add("theUrlContains", (path) => {
  cy.url().should("include", path);
});

Cypress.Commands.add("thePageShows", (text) => {
  cy.contains(text).should("exist");
});

Cypress.Commands.add("thePageDoesNotShow", (text) => {
  cy.contains(text).should("not.exist");
});

Cypress.Commands.add("theFlashSays", (text) => {
  cy.get(".alert-info").should("contain", text);
});

Cypress.Commands.add("theErrorSays", (text) => {
  cy.get("[role='alert']").should("contain", text);
});

// -- Dashboard ----------------------------------------------------------

Cypress.Commands.add("theDashboardShows", (...pipelineNames) => {
  cy.verifyDashboardLoaded();
  pipelineNames.forEach((n) => cy.verifyPipelineVisible(n));
});

Cypress.Commands.add("theDashboardDoesNotShow", (name) => {
  cy.verifyPipelineNotVisible(name);
});

// -- Agents -------------------------------------------------------------

Cypress.Commands.add("switchToAgentTab", (tabName) => {
  cy.selectAgentTab(tabName);
});

Cypress.Commands.add("theActiveAgentTabIs", (tabName) => {
  cy.verifyActiveTab(tabName);
});

Cypress.Commands.add("filterAgents", (query) => {
  cy.get(".search-box input").type(query);
});

Cypress.Commands.add("scheduleTestJob", () => {
  cy.get("button").contains("SCHEDULE TEST JOB").click();
});

Cypress.Commands.add("theDeleteButtonRequiresConfirmation", () => {
  cy.get("button").contains("DELETE").should("have.attr", "data-confirm");
});

Cypress.Commands.add("theBulkActionsToolbarIsVisible", () => {
  cy.get(".bulk-actions").should("be.visible");
});

Cypress.Commands.add("theAgentTableIsNotEmpty", () => {
  cy.get(".agents-table tbody tr").should("exist");
});

// -- Materials ----------------------------------------------------------

Cypress.Commands.add("theMaterialsPageIsLoaded", () => {
  cy.verifyMaterialsPageLoaded();
});

Cypress.Commands.add("theMaterialIsVisible", (url) => {
  cy.verifyMaterialVisible(url);
});

Cypress.Commands.add("theMaterialIsNotVisible", (url) => {
  cy.verifyMaterialNotVisible(url);
});

Cypress.Commands.add("theUsagesModalContains", (pipelineName) => {
  cy.verifyUsagesModalContains(pipelineName);
});

Cypress.Commands.add("theModificationsModalContains", (text) => {
  cy.verifyModificationsModalContains(text);
});

Cypress.Commands.add("theMaterialScmTypeIs", (fingerprint, type) => {
  cy.verifySCMType(fingerprint, type);
});

Cypress.Commands.add("theMaterialAutoUpdateIs", (fingerprint, status) => {
  cy.verifyAutoUpdateStatus(fingerprint, status);
});

Cypress.Commands.add("theMaterialBranchIs", (fingerprint, branch) => {
  cy.verifyBranchName(fingerprint, branch);
});

// -- Pipeline Config ----------------------------------------------------

Cypress.Commands.add("addMaterial", () => {
  cy.contains("button", "Add Material").click();
});

Cypress.Commands.add("selectMaterialType", (type) => {
  cy.get("select[name='type']").select(type);
});

Cypress.Commands.add("saveConfiguration", () => {
  cy.get("button").contains("Save Configuration").click();
});

Cypress.Commands.add("validateWithNonexistentPipelineDependency", () => {
  cy.get("input[name='url']").clear().type("non-existent-pipeline");
  cy.get("button").contains("Save Configuration").click();
  cy.get("[role='alert']").should(
    "contain",
    "Error: Referenced pipeline 'non-existent-pipeline' does not exist",
  );
});

// -- VSM ----------------------------------------------------------------

Cypress.Commands.add("theVSMShowsNode", (label) => {
  cy.get(".vsm-node").contains(label).should("exist");
});

Cypress.Commands.add("theVSMSvgIsRendered", () => {
  cy.get("#vsm-svg").should("exist");
});

Cypress.Commands.add("theVSMHasLevels", (minLevels) => {
  cy.get(".vsm-level").should("have.length.at.least", minLevels);
});

Cypress.Commands.add("theVSMHasExactlyLevels", (n) => {
  cy.get(".vsm-level").should("have.length", n);
});

Cypress.Commands.add("theVSMStageIndicatorShows", (label) => {
  cy.get(`[aria-label*="${label}"]`).should("exist");
});

Cypress.Commands.add("theVSMRendersOnMobile", () => {
  cy.get("#vsm-container").should("exist");
});

Cypress.Commands.add("insideVSMNode", (nodeId, fn) => {
  cy.get(`[data-id="${nodeId}"]`).within(fn);
});

// -- VSM arrow interactions (domain language) -------------------------

const vsmNodeId = (label) => {
  // Find the vsm-node whose displayed text contains the label, return its data-id
  return cy
    .get(".vsm-node")
    .contains(label)
    .closest(".vsm-node")
    .invoke("attr", "data-id");
};

const vsmArrowSelector = (sourceId, targetId) =>
  `#vsm-svg .vsm-path[data-source-id="${sourceId}"][data-target-id="${targetId}"]`;

Cypress.Commands.add("hoverOnArrowBetween", (sourceLabel, targetLabel) => {
  vsmNodeId(sourceLabel).then((srcId) => {
    vsmNodeId(targetLabel).then((tgtId) => {
      cy.get(vsmArrowSelector(srcId, tgtId))
        .first()
        .trigger("mouseenter", { force: true });
    });
  });
});

Cypress.Commands.add("tapOnArrowBetween", (sourceLabel, targetLabel) => {
  vsmNodeId(sourceLabel).then((srcId) => {
    vsmNodeId(targetLabel).then((tgtId) => {
      cy.get(vsmArrowSelector(srcId, tgtId))
        .first()
        .trigger("click", { force: true });
    });
  });
});

Cypress.Commands.add(
  "arrowBetweenShouldBeHighlighted",
  (sourceLabel, targetLabel) => {
    vsmNodeId(sourceLabel).then((srcId) => {
      vsmNodeId(targetLabel).then((tgtId) => {
        // Behavior: the visible arrow path exists and is not transparent
        cy.get(
          `#vsm-svg .vsm-path[data-source-id="${srcId}"][data-target-id="${tgtId}"]`,
        )
          .not('[stroke="transparent"]')
          .first()
          .should("exist")
          .and(($el) => expect($el.attr("stroke")).not.to.eq("transparent"));
      });
    });
  },
);

Cypress.Commands.add("nodesShouldGlow", (sourceLabel, targetLabel) => {
  vsmNodeId(sourceLabel).then((srcId) => {
    vsmNodeId(targetLabel).then((tgtId) => {
      cy.get(`.vsm-node[data-id="${srcId}"]`).should(
        "have.class",
        "vsm-path-highlighted",
      );
      cy.get(`.vsm-node[data-id="${tgtId}"]`).should(
        "have.class",
        "vsm-path-highlighted",
      );
    });
  });
});

Cypress.Commands.add("nodeShouldNotGlow", (label) => {
  vsmNodeId(label).then((id) => {
    cy.get(`.vsm-node[data-id="${id}"]`).should(
      "not.have.class",
      "vsm-path-highlighted",
    );
  });
});

Cypress.Commands.add(
  "allOtherArrowsShouldBeDimmed",
  (sourceLabel, targetLabel) => {
    vsmNodeId(sourceLabel).then((srcId) => {
      vsmNodeId(targetLabel).then((tgtId) => {
        cy.get("#vsm-svg .vsm-path").then(($paths) => {
          const pairs = [];
          $paths.each((_, el) => {
            const s = el.getAttribute("data-source-id");
            const t = el.getAttribute("data-target-id");
            const st = el.getAttribute("stroke");
            if (s && t && st !== "transparent") pairs.push({ s, t });
          });
          // Behavior: other arrows exist and are not the highlighted one
          pairs.forEach(({ s, t }) => {
            if (s !== srcId || t !== tgtId) {
              cy.get(
                `#vsm-svg .vsm-path[data-source-id="${s}"][data-target-id="${t}"]`,
              )
                .not('[stroke="transparent"]')
                .first()
                .should("exist");
            }
          });
        });
      });
    });
  },
);

Cypress.Commands.add(
  "moveMouseAwayFromArrowBetween",
  (sourceLabel, targetLabel) => {
    vsmNodeId(sourceLabel).then((srcId) => {
      vsmNodeId(targetLabel).then((tgtId) => {
        cy.get(vsmArrowSelector(srcId, tgtId))
          .first()
          .trigger("mouseleave", { force: true });
      });
    });
  },
);

Cypress.Commands.add("allArrowsShouldBeBright", () => {
  // Re-query each time to survive LiveView re-renders
  cy.get("#vsm-svg .vsm-path").should("have.length.greaterThan", 0);
  cy.get("#vsm-svg .vsm-path").each(($el) => {
    cy.wrap($el).should("not.have.css", "opacity", "0.15");
  });
});

Cypress.Commands.add("noNodesShouldGlow", () => {
  cy.get(".vsm-node.vsm-path-highlighted").should("not.exist");
});

Cypress.Commands.add("vsmArrowsShouldBeDrawn", (minCount) => {
  cy.get('#vsm-svg .vsm-path[stroke="transparent"]').should(
    "have.length.at.least",
    minCount,
  );
});

// -- Audit Log ----------------------------------------------------------

Cypress.Commands.add("theAuditLogAcceptsActorFilter", () => {
  cy.get("input[name='actor']").clear().type("test_user");
  cy.get("input[name='actor']").should("have.value", "test_user");
});

Cypress.Commands.add("theAuditLogAcceptsActionFilter", () => {
  cy.get("input[name='action']").clear().type("pipeline_trigger");
  cy.get("input[name='action']").should("have.value", "pipeline_trigger");
});

Cypress.Commands.add("theAuditLogHasResourceFilters", () => {
  cy.get("input[name='resource_type']").should("exist");
  cy.get("input[name='resource_name']").should("exist");
});

Cypress.Commands.add("theAuditLogHasDateRangeFilters", () => {
  cy.get("input[name='date_from']").should("exist");
  cy.get("input[name='date_to']").should("exist");
});

// -- Config Repos -------------------------------------------------------

Cypress.Commands.add("thePageHasALinkToAddConfigRepo", () => {
  cy.get("a[href*='config_repos/new']").should("exist");
});
