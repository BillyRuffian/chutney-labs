class FeatureFile < ApplicationRecord
  MAX_FILE_SIZE = 250.kilobytes

  validates :name, presence: true, length: { maximum: 120 }, format: {
    with: /\A[\w.-]+\.feature\z/i,
    message: 'must be a valid .feature filename'
  }
  validates :content, length: { maximum: MAX_FILE_SIZE }

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.to_s.strip.gsub(/[^\w.-]/, '-')
    self.name = "#{name}.feature" unless name.blank? || File.extname(name).present?
  end
end
