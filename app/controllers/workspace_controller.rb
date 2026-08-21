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
    @feature_files = FeatureFile.order(updated_at: :desc)
    @initial_file = @feature_files.first
    @initial_name = @initial_file&.name || 'sign_in.feature'
    @initial_content = @initial_file&.content || EXAMPLE
  end
end
