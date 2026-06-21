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
