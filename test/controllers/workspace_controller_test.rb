require 'test_helper'

class WorkspaceControllerTest < ActionDispatch::IntegrationTest
  test 'renders the complete editor workspace' do
    get root_path

    assert_response :success
    assert_select "textarea[data-workspace-target='editor']"
    assert_select "button[data-action='workspace#save']"
    assert_select "input[type='file'][accept*='.feature']"
    assert_select "[data-workspace-target='issueList']"
    assert_select "img[src='/mr_pickle.png'][width='42'][height='43']"
    assert_select "link[rel='icon'][type='image/png'][href='/mr_pickle.png']"
    assert_select "link[rel='apple-touch-icon'][href='/mr_pickle.png']"
    assert_select "[data-workspace-target='docsOverlay'][hidden]"
    assert_select '[data-workspace-create-url-value]', count: 0
    assert_select '.rail-footer', text: /Files are stored only in this browser\./
    assert_select "button[data-action='workspace#openRuleSettings']"
    assert_select "[data-workspace-target='ruleToggle']", count: 44
    assert_select "[data-workspace-target='ruleOption'][data-rule-name='RequiredTagsStartsWith'][data-option-key='Matcher']"
    assert_select "[data-workspace-target='rulesOverlay'][hidden]"
  end

  test 'does not expose server-side feature file persistence routes' do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path('/feature_files', method: :post)
    end
  end
end
