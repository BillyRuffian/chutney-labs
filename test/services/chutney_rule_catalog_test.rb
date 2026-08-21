require 'test_helper'

class ChutneyRuleCatalogTest < ActiveSupport::TestCase
  test 'lists every configurable Chutney rule with local UI metadata' do
    assert_equal 44, ChutneyRuleCatalog.rules.size
    assert_equal 40, ChutneyRuleCatalog.default_enabled_names.size
    assert_equal ChutneyRuleCatalog.rules.map(&:name).sort, ChutneyRuleCatalog.names.sort

    rule = ChutneyRuleCatalog.rules.find { it.name == 'MissingTestAction' }
    assert_equal 'Missing Test Action', rule.title
    assert_includes rule.summary, 'without a When step'
    assert rule.enabled_by_default
    assert_equal '/rules/MissingTestAction', rule.documentation_url

    configurable = ChutneyRuleCatalog.rules.find { it.name == 'RequiredTagsStartsWith' }
    assert_equal [ 'Matcher' ], configurable.settings.map(&:key)
    assert_equal :list, configurable.settings.first.type

    mutually_exclusive = ChutneyRuleCatalog.rules.find { it.name == 'AvoidMutuallyExclusiveTags' }
    assert_not mutually_exclusive.enabled_by_default
    assert_equal :groups, mutually_exclusive.settings.first.type
  end
end
