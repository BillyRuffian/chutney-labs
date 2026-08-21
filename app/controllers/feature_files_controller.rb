class FeatureFilesController < ApplicationController
  before_action :set_feature_file, only: %i[show update destroy]

  def show
    render json: serialize(@feature_file)
  end

  def create
    feature_file = FeatureFile.new(feature_file_params)
    if feature_file.save
      render json: serialize(feature_file), status: :created
    else
      render json: { errors: feature_file.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @feature_file.update(feature_file_params)
      render json: serialize(@feature_file)
    else
      render json: { errors: @feature_file.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @feature_file.destroy!
    head :no_content
  end

  private

  def set_feature_file
    @feature_file = FeatureFile.find(params[:id])
  end

  def feature_file_params
    params.expect(feature_file: %i[name content])
  end

  def serialize(feature_file)
    feature_file.as_json(only: %i[id name content updated_at])
  end
end
