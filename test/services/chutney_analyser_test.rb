require 'test_helper'

class ChutneyAnalyserTest < ActiveSupport::TestCase
  test 'returns no issues for a well formed feature' do
    result = ChutneyAnalyser.new(
      filename: 'sign_in.feature',
      content: WorkspaceController::EXAMPLE
    ).call

    assert_empty result.issues
    assert_nil result.parse_error
    assert_operator result.duration_ms, :>=, 0
  end

  test 'returns structured Chutney issues with locations' do
    result = ChutneyAnalyser.new(
      filename: 'login.feature',
      content: <<~GHERKIN
        Feature: Login
          Scenario: logs in.
            Given a user exists
            Then they sign in
      GHERKIN
    ).call

    issue = result.issues.find { |candidate| candidate[:rule] == 'MissingTestAction' }
    assert_equal 2, issue[:line]
    assert_equal 3, issue[:column]
    assert_equal 'warning', issue[:severity]
    assert_equal '/rules/MissingTestAction', issue[:documentation_url]
  end

  test 'runs only the locally selected rules' do
    content = <<~GHERKIN
      Feature: Login
        Scenario: logs in.
          Given a user exists
          Then they sign in
    GHERKIN

    disabled = ChutneyAnalyser.new(filename: 'login.feature', content:, enabled_rules: []).call
    selected = ChutneyAnalyser.new(filename: 'login.feature', content:, enabled_rules: [ 'MissingTestAction', 'NotARealRule' ]).call

    assert_empty disabled.issues
    assert_equal [ 'MissingTestAction' ], selected.issues.map { it[:rule] }.uniq
  end

  test 'rule selections do not affect later validations' do
    content = "Feature: Login\n  Scenario: logs in\n    Given a user exists\n    Then they sign in\n"

    ChutneyAnalyser.new(filename: 'login.feature', content:, enabled_rules: []).call
    result = ChutneyAnalyser.new(filename: 'login.feature', content:).call

    assert result.issues.any? { it[:rule] == 'MissingTestAction' }
  end

  test 'applies list and numeric options to configurable rules' do
    tagged_content = <<~GHERKIN
      @OTHER-1
      Feature: Login
        A useful description
        Scenario: logs in
          Given a user exists
          When they sign in
          Then they see an account
    GHERKIN
    long_content = <<~GHERKIN
      Feature: Login
        A useful description
        Scenario: logs in
          Given a user exists
          When they sign in
          Then they see an account
    GHERKIN

    tags = ChutneyAnalyser.new(
      filename: 'login.feature',
      content: tagged_content,
      enabled_rules: [ 'RequiredTagsStartsWith' ],
      rule_options: { 'RequiredTagsStartsWith' => { 'Matcher' => [ 'JIRA' ] } }
    ).call
    steps = ChutneyAnalyser.new(
      filename: 'login.feature',
      content: long_content,
      enabled_rules: [ 'TooManySteps' ],
      rule_options: { 'TooManySteps' => { 'MaxCount' => 2 } }
    ).call

    assert_equal [ 'RequiredTagsStartsWith' ], tags.issues.map { it[:rule] }.uniq
    assert_equal [ 'TooManySteps' ], steps.issues.map { it[:rule] }.uniq
  end

  test 'does not require tag prefixes when a feature has no tags' do
    result = ChutneyAnalyser.new(
      filename: 'sign_in.feature',
      content: WorkspaceController::EXAMPLE,
      enabled_rules: [ 'RequiredTagsStartsWith' ],
      rule_options: { 'RequiredTagsStartsWith' => { 'Matcher' => [ 'JIRA' ] } }
    ).call

    assert_empty result.issues
  end

  test 'turns parser failures into a line-specific syntax issue' do
    result = ChutneyAnalyser.new(filename: 'broken.feature', content: "Feature broken\n").call

    assert result.parse_error
    assert_equal 'GherkinSyntax', result.issues.first[:rule]
    assert_equal 'error', result.issues.first[:severity]
    assert_equal 1, result.issues.first[:line]
    assert_includes result.issues.first[:message], 'Invalid Gherkin at line 1, column 1.'
    assert_includes result.issues.first[:message], 'Add the missing colon: “Feature: broken”.'
    refute_match(/CukeModeler|chutney-online|\.rb:/, result.issues.first[:message])
  end

  test 'turns Chutney failures on malformed examples into actionable syntax help' do
    result = ChutneyAnalyser.new(
      filename: 'login.feature',
      content: <<~GHERKIN
        Feature: Login
          A useful description

          Scenario Outline: login
            Given <user> exists

            Examples:
              bob
      GHERKIN
    ).call

    issue = result.issues.first
    assert result.parse_error
    assert_equal 'GherkinSyntax', issue[:rule]
    assert_equal 7, issue[:line]
    assert_includes issue[:message], 'Add a pipe-delimited header and at least one data row'
    refute_match(/undefined method|NoMethodError|\.rb:/, issue[:message])
  end

  test 'does not carry scenario or tag state between validations' do
    first = <<~GHERKIN
      @smoke
      Feature: First
        A useful description

        Scenario: first flow
          Given a shared setup
          When a shared action
          Then a shared outcome
    GHERKIN
    second = <<~GHERKIN
      @Smoke
      Feature: Second
        Another useful description

        Scenario: second flow
          Given a shared setup
          When a shared action
          Then a shared outcome
    GHERKIN

    ChutneyAnalyser.new(content: first, filename: 'first.feature').call
    result = ChutneyAnalyser.new(content: second, filename: 'second.feature').call

    assert_empty result.issues.select { |issue| issue[:rule] == 'SameScenario' }
    assert_empty result.issues.select { |issue| issue[:rule] == 'SameTagDifferentCase' }
  end

  test 'still compares scenarios and tag casing within one validation' do
    content = <<~GHERKIN
      Feature: Duplicate checks
        A useful description

        @smoke
        Scenario: first flow
          Given a shared setup
          When a shared action
          Then a shared outcome

        @Smoke
        Scenario: second flow
          Given a shared setup
          When a shared action
          Then a shared outcome
    GHERKIN

    result = ChutneyAnalyser.new(content:, filename: 'duplicate_checks.feature').call

    assert result.issues.any? { |issue| issue[:rule] == 'SameScenario' }
    assert result.issues.any? { |issue| issue[:rule] == 'SameTagDifferentCase' }
  end
end
