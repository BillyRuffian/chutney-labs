require 'application_system_test_case'

class WorkspaceTest < ApplicationSystemTestCase
  test 'editing, linting and saving a feature' do
    visit root_path

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
    assert_text 'online_checkout.feature saved'
    assert_selector '.file-item.is-active', text: 'online_checkout.feature'

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
    visit root_path

    attach_file Rails.root.join('test/fixtures/files/uploaded_checkout.feature'), make_visible: true

    assert_equal 'uploaded_checkout.feature', find("input[data-workspace-target='filename']").value
    assert_includes find("textarea[data-workspace-target='editor']").value, 'Feature: Uploaded checkout'
    assert_text 'loaded — save it to keep it here'
  end

  test 'newlines preserve indentation while tab indents and shift tab outdents' do
    visit root_path
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
end
