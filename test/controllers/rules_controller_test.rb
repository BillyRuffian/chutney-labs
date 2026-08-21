require 'test_helper'

class RulesControllerTest < ActionDispatch::IntegrationTest
  test 'returns in-app documentation for a known rule' do
    get rule_documentation_path('MissingTestAction'), as: :json

    assert_response :success
    assert_equal 'Missing Test Action', response.parsed_body['title']
    assert response.parsed_body['blocks'].any? { it['type'] == 'code' }
  end

  test 'does not expose arbitrary files as documentation' do
    get rule_documentation_path('UnknownRule'), as: :json

    assert_response :not_found
  end
end
