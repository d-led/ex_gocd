const SELECTORS = {
  dashboard: '.dashboard',
  pipeline: '.pipeline',
  pipelineName: '.pipeline_name',
  playButton: '.pipeline_btn.play',
  pauseButton: '.pipeline_btn.pause',
  stageList: '.pipeline_stages',
  stageBlock: '.pipeline_stage',
  searchInput: '#pipeline-search',
  dropdown: '.c-dropdown',
  dropdownItem: '.c-dropdown-item',
  
  agentsPage: '.agents-page',
  tabButton: '.tab-button',
  agentTable: '.agents-table',
  agentRow: '.agents-table tbody tr',
  agentName: '.agent-name',
  selectAllCheckbox: '.agents-table thead .checkbox-cell input',
  agentCheckbox: '.checkbox-cell input',
  
  historyPage: '.agent-job-history-page',
  historyRow: '.job-history-table tbody tr',
  jobLink: '.job-link',
  paginationButton: '.btn-pagination',
  
  detailPage: '.agent-job-run-detail-page',
  consoleLog: '.console-log',
  cancelButton: '.btn-danger',
  
  materialsPage: '.materials-page',
  materialsList: '.materials-list',
  materialCard: '.material-card',
  materialSearchInput: '#material-search',
  materialUrl: '.material-url',
  materialPipelineBadge: '.material-pipeline-badge',

  // Modal selectors
  usagesModal: '#usages-modal',
  usagesModalOk: '#usages-modal-ok',
  modificationsModal: '#modifications-modal',
  modificationsModalOk: '#modifications-modal-ok',
  modificationsSearchInput: '#mod-search-form input',
  modRow: '.mod-row'
};

Cypress.Commands.add('verifyDashboardLoaded', () => {
  cy.get(SELECTORS.dashboard).should('exist');
});

Cypress.Commands.add('verifyPipelineVisible', (name) => {
  cy.get(SELECTORS.pipeline).contains(SELECTORS.pipelineName, name).should('be.visible');
});

Cypress.Commands.add('verifyPipelineNotVisible', (name) => {
  cy.get(SELECTORS.pipelineName).contains(name).should('not.exist');
});

Cypress.Commands.add('triggerPipeline', (name) => {
  cy.get(SELECTORS.pipeline)
    .contains(SELECTORS.pipelineName, name)
    .parents(SELECTORS.pipeline)
    .find(SELECTORS.playButton)
    .click();
});

Cypress.Commands.add('searchPipelines', (query) => {
  if (query === '') {
    cy.get(SELECTORS.searchInput).clear();
  } else {
    cy.get(SELECTORS.searchInput).clear().type(query);
  }
});

Cypress.Commands.add('verifyActiveTab', (text) => {
  cy.get(SELECTORS.tabButton + '.active').should('contain', text);
});

Cypress.Commands.add('selectAgentTab', (text) => {
  cy.get(SELECTORS.tabButton).contains(text).click();
});

Cypress.Commands.add('verifyAgentExists', (hostname) => {
  cy.get(SELECTORS.agentName).contains(hostname).should('exist');
});

Cypress.Commands.add('verifyAgentNotExist', (hostname) => {
  cy.get(SELECTORS.agentName).contains(hostname).should('not.exist');
});

Cypress.Commands.add('verifyAgentState', (hostname, state) => {
  const cssClass = '.status-' + state.toLowerCase().replace('_', '-');
  cy.get(SELECTORS.agentRow)
    .contains(hostname)
    .parents('tr')
    .find(cssClass)
    .should('exist');
});

Cypress.Commands.add('toggleAgentSelection', (hostname) => {
  cy.get(SELECTORS.agentRow)
    .contains(hostname)
    .parents('tr')
    .find(SELECTORS.agentCheckbox)
    .click();
});

Cypress.Commands.add('toggleSelectAllAgents', () => {
  cy.get(SELECTORS.selectAllCheckbox).click();
});

Cypress.Commands.add('performBulkAction', (action) => {
  const btnText = action.toUpperCase();
  cy.get('.bulk-actions button').contains(btnText).click();
});

Cypress.Commands.add('verifyJobHistoryPage', (hostname) => {
  cy.get(SELECTORS.historyPage).should('exist');
  cy.get('.agent-info').should('contain', hostname);
});

Cypress.Commands.add('clickJobHistoryLink', (hostname) => {
  cy.get(SELECTORS.agentRow)
    .contains(hostname)
    .click();
});

Cypress.Commands.add('clickJobHistoryRowLink', (jobName) => {
  cy.get(SELECTORS.historyRow)
    .contains(jobName)
    .click();
});

Cypress.Commands.add('verifyConsoleLogsVisible', (jobName) => {
  cy.get(SELECTORS.detailPage).should('exist');
  cy.get(SELECTORS.detailPage + ' h1').should('contain', jobName);
  cy.get(SELECTORS.consoleLog).should('exist');
});

Cypress.Commands.add('verifyMaterialsPageLoaded', () => {
  cy.get(SELECTORS.materialsPage).should('exist');
});

Cypress.Commands.add('searchMaterials', (query) => {
  if (query === '') {
    cy.get(SELECTORS.materialSearchInput).clear();
  } else {
    cy.get(SELECTORS.materialSearchInput).clear().type(query);
  }
});

Cypress.Commands.add('verifyMaterialVisible', (url) => {
  cy.get(SELECTORS.materialUrl).contains(url).should('be.visible');
});

Cypress.Commands.add('verifyMaterialNotVisible', (url) => {
  cy.get(SELECTORS.materialUrl).contains(url).should('not.exist');
});

Cypress.Commands.add('verifySCMType', (fingerprint, type) => {
  cy.get(`#material-${fingerprint} .scm-logo-box`).should('contain', type);
});

Cypress.Commands.add('expandMaterialCard', (fingerprint) => {
  cy.get(`#material-${fingerprint} .collapse-header`).click();
});

Cypress.Commands.add('verifyAutoUpdateStatus', (fingerprint, status) => {
  cy.get(`#material-${fingerprint} .collapse-body`).should('contain', 'Auto Update').and('contain', status);
});

Cypress.Commands.add('verifyBranchName', (fingerprint, branchName) => {
  cy.get(`#material-${fingerprint} .collapse-body`).should('contain', 'Branch').and('contain', branchName);
});

Cypress.Commands.add('openUsagesModal', (fingerprint) => {
  cy.get(`#material-${fingerprint} [data-test-id="show-usages"]`).click();
});

Cypress.Commands.add('verifyUsagesModalContains', (pipelineName) => {
  cy.get(SELECTORS.usagesModal).should('be.visible').and('contain', pipelineName);
});

Cypress.Commands.add('clickUsagesModalPipelineLink', (pipelineName) => {
  cy.get(SELECTORS.usagesModal).find('.pipeline-link').contains(pipelineName).click();
});

Cypress.Commands.add('closeUsagesModal', () => {
  cy.get(SELECTORS.usagesModalOk).click();
});

Cypress.Commands.add('openModificationsModal', (fingerprint) => {
  cy.get(`#material-${fingerprint} [data-test-id="show-modifications"]`).click();
});

Cypress.Commands.add('verifyModificationsModalContains', (text) => {
  cy.get(SELECTORS.modificationsModal).should('be.visible').and('contain', text);
});

Cypress.Commands.add('searchModificationsInModal', (query) => {
  cy.get(SELECTORS.modificationsSearchInput).clear().type(query);
});

Cypress.Commands.add('closeModificationsModal', () => {
  cy.get(SELECTORS.modificationsModalOk).click();
});

// --- Screenshot helpers ---

Cypress.Commands.add('appScreenshot', (name) => {
  const specName = Cypress.spec.name.replace(/\.cy\.(js|ts|jsx|tsx)$/, '');
  const src = `cypress/screenshots/${specName}.cy.js/${name}.png`;
  const dest = `docs/screenshots/${name}.png`;
  cy.screenshot(name, { capture: 'viewport' });
  cy.task('copyScreenshot', { src, dest }, { log: false }).then((res) => {
    if (res && res.error) throw new Error(res.error);
  });
});

// --- Auth helpers ---

Cypress.Commands.add('loginAsAdmin', () => {
  cy.session('admin', () => {
    cy.visit('/auth/login');
    cy.get('#session_username').type('admin');
    cy.get('.btn-login').click();
    cy.url().should('eq', Cypress.config().baseUrl + '/');
  });
});

// ============================================================
// Domain Language Commands
//
// Compose technical commands into behavior-level steps so
// tests read like plain English. When the DOM or framework
// details change, fix only these commands — tests stay untouched.
// ============================================================

// -- App / Navigation ---------------------------------------------------

/** Visit a LiveView page and wait until the socket connects. */
Cypress.Commands.add('visitPage', (path) => {
  cy.visit(path);
  cy.get('.phx-connected', { timeout: 10000 }).should('exist');
});

/** Click a button by its visible label. */
Cypress.Commands.add('iClickButton', (label) => {
  cy.get('button').contains(label).click();
});

/** Click a link by its visible text. */
Cypress.Commands.add('iClickLink', (label) => {
  cy.get('a').contains(label).click();
});

/** Assert the current URL includes the given path segment. */
Cypress.Commands.add('theUrlContains', (path) => {
  cy.url().should('include', path);
});

/** Assert some visible text appears on the page. */
Cypress.Commands.add('thePageShows', (text) => {
  cy.contains(text).should('exist');
});

/** Assert an element matching the selector is visible. */
Cypress.Commands.add('theElementIsVisible', (selector) => {
  cy.get(selector).should('be.visible');
});

/** Assert a success / info flash message is shown. */
Cypress.Commands.add('theFlashSays', (text) => {
  cy.get('.alert-info').should('contain', text);
});

/** Assert an error alert message is shown. */
Cypress.Commands.add('theErrorSays', (text) => {
  cy.get("[role='alert']").should('contain', text);
});

/** Type into a form field identified by its name attribute. */
Cypress.Commands.add('iTypeInto', (fieldName, value) => {
  cy.get(`input[name="${fieldName}"]`).clear().type(value);
});

/** Select an option from a <select> identified by its name attribute. */
Cypress.Commands.add('iSelectOption', (selectName, value) => {
  cy.get(`select[name="${selectName}"]`).select(value);
});

// -- Dashboard ----------------------------------------------------------

/** The dashboard is loaded and shows the given pipelines. */
Cypress.Commands.add('theDashboardShows', (...pipelineNames) => {
  cy.verifyDashboardLoaded();
  pipelineNames.forEach(n => cy.verifyPipelineVisible(n));
});

/** The dashboard does NOT show a given pipeline. */
Cypress.Commands.add('theDashboardDoesNotShow', (name) => {
  cy.verifyPipelineNotVisible(name);
});

/** Search for pipelines on the dashboard. */
Cypress.Commands.add('iSearchPipelines', (query) => {
  cy.searchPipelines(query);
});

/** Trigger a pipeline run from the dashboard. */
Cypress.Commands.add('iTriggerPipelineRun', (name) => {
  cy.triggerPipeline(name);
});

// -- Agents -------------------------------------------------------------

/** Switch to a named agent tab (STATIC / ELASTIC). */
Cypress.Commands.add('iSwitchToAgentTab', (tabName) => {
  cy.selectAgentTab(tabName);
});

/** Assert the given agent tab is active. */
Cypress.Commands.add('theActiveAgentTabIs', (tabName) => {
  cy.verifyActiveTab(tabName);
});

/** Filter agents via the search box. */
Cypress.Commands.add('iFilterAgents', (query) => {
  cy.get('.search-box input').type(query);
});

// -- Materials ----------------------------------------------------------

/** The materials page is loaded. */
Cypress.Commands.add('theMaterialsPageIsLoaded', () => {
  cy.verifyMaterialsPageLoaded();
});

/** A material with the given URL is visible. */
Cypress.Commands.add('theMaterialIsVisible', (url) => {
  cy.verifyMaterialVisible(url);
});

/** A material with the given URL is NOT visible. */
Cypress.Commands.add('theMaterialIsNotVisible', (url) => {
  cy.verifyMaterialNotVisible(url);
});

/** Search materials by query. */
Cypress.Commands.add('iSearchMaterials', (query) => {
  cy.searchMaterials(query);
});

/** Expand a material card by fingerprint. */
Cypress.Commands.add('iExpandMaterial', (fingerprint) => {
  cy.expandMaterialCard(fingerprint);
});

/** Open the Usages modal for a material. */
Cypress.Commands.add('iOpenUsagesModal', (fingerprint) => {
  cy.openUsagesModal(fingerprint);
});

/** Assert the Usages modal contains a pipeline name. */
Cypress.Commands.add('theUsagesModalContains', (pipelineName) => {
  cy.verifyUsagesModalContains(pipelineName);
});

/** Click a pipeline link inside the Usages modal. */
Cypress.Commands.add('iClickUsagesModalPipelineLink', (pipelineName) => {
  cy.clickUsagesModalPipelineLink(pipelineName);
});

/** Close the Usages modal. */
Cypress.Commands.add('iCloseUsagesModal', () => {
  cy.closeUsagesModal();
});

/** Open the Modifications modal for a material. */
Cypress.Commands.add('iOpenModificationsModal', (fingerprint) => {
  cy.openModificationsModal(fingerprint);
});

/** Assert the Modifications modal contains some text. */
Cypress.Commands.add('theModificationsModalContains', (text) => {
  cy.verifyModificationsModalContains(text);
});

/** Search inside the Modifications modal. */
Cypress.Commands.add('iSearchModifications', (query) => {
  cy.searchModificationsInModal(query);
});

/** Close the Modifications modal. */
Cypress.Commands.add('iCloseModificationsModal', () => {
  cy.closeModificationsModal();
});

/** Assert the material's SCM type icon matches. */
Cypress.Commands.add('theMaterialScmTypeIs', (fingerprint, type) => {
  cy.verifySCMType(fingerprint, type);
});

/** Assert auto-update status in expanded material card. */
Cypress.Commands.add('theMaterialAutoUpdateIs', (fingerprint, status) => {
  cy.verifyAutoUpdateStatus(fingerprint, status);
});

/** Assert branch name in expanded material card. */
Cypress.Commands.add('theMaterialBranchIs', (fingerprint, branch) => {
  cy.verifyBranchName(fingerprint, branch);
});

// -- Pipeline Config ----------------------------------------------------

/** Click the Add Material button on the pipeline config page. */
Cypress.Commands.add('iAddMaterial', () => {
  cy.get('button').contains('Add Material').click();
});

/** Select a material type in the pipeline config form. */
Cypress.Commands.add('iSelectMaterialType', (type) => {
  cy.get("select[name='type']").select(type);
});

/** Click Save Configuration. */
Cypress.Commands.add('iSaveConfiguration', () => {
  cy.get('button').contains('Save Configuration').click();
});

// -- VSM ----------------------------------------------------------------

/** Assert a VSM node with the given label exists. */
Cypress.Commands.add('theVSMShowsNode', (label) => {
  cy.get('.vsm-node').contains(label).should('exist');
});

/** Assert the VSM SVG is rendered. */
Cypress.Commands.add('theVSMSvgIsRendered', () => {
  cy.get('#vsm-svg').should('exist');
});

/** Assert the VSM has at least N levels. */
Cypress.Commands.add('theVSMHasLevels', (minLevels) => {
  cy.get('.vsm-level').should('have.length.at.least', minLevels);
});
