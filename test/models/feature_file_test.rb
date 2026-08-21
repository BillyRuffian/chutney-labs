require 'test_helper'

class FeatureFileTest < ActiveSupport::TestCase
  test 'normalizes a feature filename' do
    feature_file = FeatureFile.new(name: 'My login', content: 'Feature: Login')

    assert feature_file.valid?
    assert_equal 'My-login.feature', feature_file.name
  end

  test 'rejects non feature extensions and oversized content' do
    feature_file = FeatureFile.new(name: 'notes.txt', content: 'x' * (FeatureFile::MAX_FILE_SIZE + 1))

    assert_not feature_file.valid?
    assert_includes feature_file.errors[:name], 'must be a valid .feature filename'
    assert feature_file.errors[:content].any?
  end
end
