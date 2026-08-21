require 'test_helper'

class LintControllerTest < ActionDispatch::IntegrationTest
  test 'runs Chutney and returns structured results' do
    post lint_path, params: {
      filename: 'login.feature',
      content: "Feature: Login\n  Scenario: login\n    Given a user\n    Then success\n"
    }, as: :json

    assert_response :success
    assert_equal false, response.parsed_body['valid']
    assert response.parsed_body['issues'].any? { |issue| issue['line'] == 2 }
    assert_equal Chutney::VERSION, response.parsed_body['chutney_version']
  end

  test 'rejects oversized input before linting' do
    post lint_path, params: {
      filename: 'huge.feature',
      content: 'x' * (LintController::MAX_CONTENT_SIZE + 1)
    }, as: :json

    assert_response :content_too_large
  end

  test 'applies only whitelisted rules requested by the browser' do
    post lint_path, params: {
      filename: 'login.feature',
      content: "Feature: Login\n  Scenario: login\n    Given a user\n    Then success\n",
      rules: [ 'MissingTestAction', 'Kernel' ]
    }, as: :json

    assert_response :success
    assert_equal [ 'MissingTestAction' ], response.parsed_body['issues'].map { it['rule'] }.uniq
  end

  test 'normalizes and applies configurable rule options' do
    post lint_path, params: {
      filename: 'login.feature',
      content: "@OTHER-1\nFeature: Login\n  A useful description\n  Scenario: login\n    Given a user\n    When action\n    Then success\n",
      rules: [ 'RequiredTagsStartsWith' ],
      rule_options: { RequiredTagsStartsWith: { Matcher: [ '@JIRA', 'PROJECT' ] } }
    }, as: :json

    assert_response :success
    assert_equal [ 'RequiredTagsStartsWith' ], response.parsed_body['issues'].map { it['rule'] }.uniq
  end

  test 'rejects invalid regular expression options' do
    post lint_path, params: {
      filename: 'login.feature',
      content: "Feature: Login\n  Scenario: login\n    Given a user\n",
      rules: [ 'ScenarioNamesMatch' ],
      rule_options: { ScenarioNamesMatch: { Matcher: '[' } }
    }, as: :json

    assert_response :unprocessable_content
    assert_includes response.parsed_body['error'], 'not a valid regular expression'
  end

  test 'applies nested mutually exclusive tag groups' do
    post lint_path, params: {
      filename: 'responsive.feature',
      content: "@mobile @desktop\nFeature: Responsive\n  A useful description\n  Scenario: homepage\n    Given a user\n    When they visit\n    Then it responds\n",
      rules: [ 'AvoidMutuallyExclusiveTags' ],
      rule_options: { AvoidMutuallyExclusiveTags: { TagGroups: [ [ 'mobile', 'desktop' ] ] } }
    }, as: :json

    assert_response :success
    assert_equal [ 'AvoidMutuallyExclusiveTags' ], response.parsed_body['issues'].map { it['rule'] }.uniq
  end
end
