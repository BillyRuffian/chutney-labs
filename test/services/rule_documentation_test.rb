require 'test_helper'

class RuleDocumentationTest < ActiveSupport::TestCase
  test 'loads and structures the documentation shipped with Chutney' do
    documentation = RuleDocumentation.fetch('MissingTestAction')

    assert_equal 'Missing Test Action', documentation[:title]
    assert documentation[:blocks].any? { it[:type] == 'paragraph' && it[:content].include?('without a When step') }
    assert documentation[:blocks].any? { it[:type] == 'code' && it[:content].include?('When I log in') }
    assert_equal 'https://www.usechutney.com/docs/rules/missing-test-action', documentation[:external_url]
  end

  test 'maps documentation filename exceptions and rejects unknown rules' do
    assert RuleDocumentation.available?('InvalidFileName')
    assert_equal 'invalid_file_name', RuleDocumentation.slug_for('InvalidFileName')
    assert_nil RuleDocumentation.fetch('../../Gemfile')
  end
end
