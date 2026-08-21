Feature: Uploaded checkout
  As a customer
  I want to upload a feature
  So that I can lint it online

  Scenario: upload a feature file
    Given I have a Gherkin feature file
    When I upload it to Chutney Lab
    Then I can edit and lint its contents
