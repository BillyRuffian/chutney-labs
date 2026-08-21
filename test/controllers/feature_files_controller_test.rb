require 'test_helper'

class FeatureFilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @feature_file = FeatureFile.create!(name: 'existing.feature', content: 'Feature: Existing')
  end

  test 'creates, reads, updates and deletes feature files' do
    assert_difference('FeatureFile.count', 1) do
      post feature_files_path, params: {
        feature_file: { name: 'checkout', content: 'Feature: Checkout' }
      }, as: :json
    end
    created = response.parsed_body
    assert_response :created
    assert_equal 'checkout.feature', created['name']

    get feature_file_path(created['id']), as: :json
    assert_response :success
    assert_equal 'Feature: Checkout', response.parsed_body['content']

    patch feature_file_path(created['id']), params: {
      feature_file: { content: 'Feature: Updated checkout' }
    }, as: :json
    assert_response :success
    assert_equal 'Feature: Updated checkout', response.parsed_body['content']

    assert_difference('FeatureFile.count', -1) do
      delete feature_file_path(created['id']), as: :json
    end
    assert_response :no_content
  end

  test 'returns validation errors as json' do
    post feature_files_path, params: { feature_file: { name: 'notes.txt', content: '' } }, as: :json

    assert_response :unprocessable_entity
    assert response.parsed_body['errors'].any?
  end
end
