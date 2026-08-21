require 'application_system_test_case'

class WorkspaceTest < ApplicationSystemTestCase
  setup do
    visit root_path
    page.execute_script('localStorage.clear()')
    visit root_path
  end

  test 'editing, linting and saving a feature' do
    assert_selector '.tok-section', text: 'Feature:'
    assert_text 'Beautifully seasoned'

    find("input[data-workspace-target='filename']").set('online_checkout')
    find("textarea[data-workspace-target='editor']").set(<<~GHERKIN)
      Feature: Online checkout
        Scenario: complete purchase
          Given a product is in my basket
          Then I see a receipt
    GHERKIN
    click_button 'Run Chutney'

    assert_text 'Missing Test Action'
    assert_selector '.editor-line.has-issue'

    within('.issue-card', text: 'Missing Test Action') do
      click_button 'Read rule guide'
    end
    assert_selector '.docs-drawer', text: 'Missing Test Action'
    assert_text 'without a When step'
    assert_selector '.docs-content pre', text: 'When I log in'
    find('.docs-close').click

    click_button 'Save changes'
    assert_text 'online_checkout.feature saved in this browser'
    assert_selector '.file-item.is-active', text: 'online_checkout.feature'

    workspace = page.evaluate_script("JSON.parse(localStorage.getItem('chutney.workspace.v1'))")
    assert_equal 'online_checkout.feature', workspace['files'].first['name']
    assert_includes workspace['files'].first['content'], 'Feature: Online checkout'

    find("textarea[data-workspace-target='editor']").set(<<~GHERKIN)
      Feature: Online checkout
        As a customer
        I want to complete my order
        So that I can receive my products

        Scenario: complete purchase
          Given a product is in my basket
          When I pay with valid card details
          Then I see a receipt
    GHERKIN
    click_button 'Save changes'
    visit root_path

    assert_includes find("textarea[data-workspace-target='editor']").value, 'When I pay with valid card details'
  end

  test 'uploading a feature loads it into a new editable document' do
    attach_file Rails.root.join('test/fixtures/files/uploaded_checkout.feature'), make_visible: true

    assert_equal 'uploaded_checkout.feature', find("input[data-workspace-target='filename']").value
    assert_includes find("textarea[data-workspace-target='editor']").value, 'Feature: Uploaded checkout'
    assert_text 'loaded — save it in this browser to keep it'
  end

  test 'deleting saved files updates local storage and survives reload' do
    filename = find("input[data-workspace-target='filename']")
    editor = find("textarea[data-workspace-target='editor']")

    filename.set('first')
    editor.set("Feature: First\n  Scenario: first file\n    Given one\n    When two\n    Then three")
    click_button 'Save changes'

    find("button[data-action='workspace#newFile']").click
    filename.set('second')
    editor.set("Feature: Second\n  Scenario: second file\n    Given one\n    When two\n    Then three")
    click_button 'Save changes'
    assert_selector '.file-item', count: 2

    accept_confirm(/Delete "second\.feature" from this browser/) do
      find('.file-item', text: 'second.feature').find('.file-delete').click
    end

    assert_text 'second.feature deleted from this browser'
    assert_no_selector '.file-item', text: 'second.feature'
    assert_equal 'first.feature', filename.value

    workspace = page.evaluate_script("JSON.parse(localStorage.getItem('chutney.workspace.v1'))")
    assert_equal [ 'first.feature' ], workspace['files'].map { |file| file['name'] }

    visit root_path
    assert_selector '.file-item.is-active', text: 'first.feature'

    accept_confirm(/Delete "first\.feature" from this browser/) do
      find('.file-item', text: 'first.feature').find('.file-delete').click
    end

    assert_selector '.empty-files', text: 'Features saved in this browser will live here.'
    assert_equal [], page.evaluate_script("JSON.parse(localStorage.getItem('chutney.workspace.v1')).files")

    visit root_path
    assert_no_selector '.file-item'
  end

  test 'newlines preserve indentation while tab indents and shift tab outdents' do
    editor = find("textarea[data-workspace-target='editor']")
    editor.set("Feature: Editing\n  Scenario: keyboard flow\n    Given an existing step")

    editor.send_keys(:enter, 'And another step')
    assert_includes editor.value, "\n    And another step"

    editor.send_keys(:enter, :tab, 'Then an over-indented step')
    assert_includes editor.value, "\n      Then an over-indented step"

    editor.send_keys([ :shift, :tab ])
    assert_includes editor.value, "\n    Then an over-indented step"
    refute_includes editor.value, "\n      Then an over-indented step"
  end

  test 'rule preferences are searchable, affect linting and persist locally' do
    editor = find("textarea[data-workspace-target='editor']")
    content = "Feature: Login\n  Scenario: login\n    Given a user exists\n    Then success\n"
    editor.set(content)
    click_button 'Run Chutney'
    assert_text 'Missing Test Action'

    click_button 'Rules'
    assert_selector '.rules-drawer', text: 'Season your checks'
    assert_text '40/44'

    within('.rules-drawer') do
      fill_in 'Search linting rules', with: 'missing test action'
      assert_selector '.rule-option:not(.is-hidden)', count: 1
      find('.rule-option', text: 'Missing Test Action').find('.rule-switch').click
      click_button 'Done'
    end

    assert_no_text 'Missing Test Action'
    settings = page.evaluate_script("JSON.parse(localStorage.getItem('chutney.rules.v1'))")
    assert_not_includes settings['enabledRules'], 'MissingTestAction'

    visit root_path
    click_button 'Rules'
    toggle = find("input[value='MissingTestAction']", visible: :all)
    assert_not toggle.checked?
    click_button 'Done'

    editor = find("textarea[data-workspace-target='editor']")
    editor.set(content)
    click_button 'Run Chutney'
    assert_no_text 'Missing Test Action'

    click_button 'Rules'
    within('.rules-drawer') { click_button 'Restore defaults' }
    click_button 'Done'
    assert_text 'Missing Test Action'
  end

  test 'configurable rule details persist and affect linting' do
    click_button 'Rules'
    within('.rules-drawer') do
      fill_in 'Search linting rules', with: 'required tags starts with'
      option = find('.rule-option', text: 'Required Tags Starts With')
      option.find('.rule-switch').click
      fill_in 'Allowed tag prefixes', with: 'JIRA, PROJECT'
      click_button 'Done'
    end

    click_button 'Run Chutney'
    assert_no_text 'Required Tags Starts With'

    editor = find("textarea[data-workspace-target='editor']")
    editor.set(<<~GHERKIN)
      @OTHER-1
      Feature: Login
        A useful description
        Scenario: login
          Given a user exists
          When they sign in
          Then they see an account
    GHERKIN
    click_button 'Run Chutney'
    assert_text 'Required Tags Starts With'

    settings = page.evaluate_script("JSON.parse(localStorage.getItem('chutney.rules.v1'))")
    assert_equal [ 'JIRA', 'PROJECT' ], settings.dig('ruleOptions', 'RequiredTagsStartsWith', 'Matcher')

    visit root_path
    click_button 'Rules'
    within('.rules-drawer') do
      fill_in 'Search linting rules', with: 'required tags starts with'
      assert_field 'Allowed tag prefixes', with: 'JIRA, PROJECT'
    end
  end
end
