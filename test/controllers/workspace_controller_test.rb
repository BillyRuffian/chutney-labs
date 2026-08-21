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
    assert_select "[data-workspace-target='docsOverlay'][hidden]"
  end
end
