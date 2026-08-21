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
      content: 'x' * (FeatureFile::MAX_FILE_SIZE + 1)
    }, as: :json

    assert_response :content_too_large
  end
end
