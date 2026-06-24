/// <reference types="cypress" />

describe("Console Log Fold (Collapsible Sections)", () => {
  const FOLD_URL = "/go/tab/build/detail/demo/4/build/1/default";
  const READY = { timeout: 10000 };

  beforeEach(function () {
    cy.request({ url: FOLD_URL, failOnStatusCode: false }).then((resp) => {
      if (resp.status !== 200) {
        this.skip();
        return;
      }
      cy.visit(FOLD_URL);
      cy.get(".phx-connected", READY);
      cy.get("#console-container", READY);
      // Skip if no fold data seeded
      cy.get("body").then(($body) => {
        if ($body.find(".fold-start").length === 0) {
          this.skip();
        }
      });
    });
  });

  it("renders fold headers with section names", function () {
    cy.get(".fold-start").should("have.length", 4);
    cy.get(".fold-start .log-message").first().should("contain.text", "Git Checkout");
    cy.get(".fold-start .log-message").eq(1).should("contain.text", "Install Dependencies");
    cy.get(".fold-start .log-message").eq(2).should("contain.text", "Compile");
    cy.get(".fold-start .log-message").eq(3).should("contain.text", "Run Tests");
  });

  it("hides ##[endfold] markers", function () {
    cy.get("[data-fold-end='true']").each(($el) => {
      cy.wrap($el).should("have.class", "hidden");
    });
  });

  it("collapses all sections on Collapse All click", function () {
    cy.contains("button", "Collapse All").click();
    cy.wait(400);
    cy.get(".fold-start.collapsed").should("have.length", 4);
    cy.get("#log-lines-stream .log-row:not(.hidden)").should("have.length.at.most", 6);
    cy.get("#log-lines-stream").should("contain.text", "Build completed successfully!");
  });

  it("expands all sections on Expand All click", function () {
    cy.contains("button", "Collapse All").click();
    cy.wait(400);
    cy.contains("button", "Expand All").click();
    cy.wait(400);
    cy.get(".fold-start.collapsed").should("have.length", 0);
    cy.get("#log-lines-stream .log-row:not(.hidden)").should("have.length.of.at.least", 17);
  });
});
