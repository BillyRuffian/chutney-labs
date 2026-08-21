class WorkspaceController < ApplicationController
  EXAMPLE = <<~GHERKIN.freeze
    Feature: Sign in
      As a returning customer
      I want to sign in to my account
      So that I can see my recent orders

      Scenario: Sign in with valid details
        Given I have an existing account
        When I sign in with valid details
        Then I should see my account overview
  GHERKIN

  def index
    @initial_name = 'sign_in.feature'
    @initial_content = EXAMPLE
  end
end
