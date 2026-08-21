class LintController < ApplicationController
  MAX_CONTENT_SIZE = 250.kilobytes

  def create
    content = params[:content].to_s
    if content.bytesize > MAX_CONTENT_SIZE
      return render json: { error: 'Feature files must be smaller than 250 KB.' }, status: :content_too_large
    end

    enabled_rules = Array(params[:rules]).map(&:to_s) if params.key?(:rules)
    normalization = ChutneyRuleCatalog.normalize_options(params[:rule_options])
    if normalization.errors.any?
      return render json: { error: normalization.errors.to_sentence }, status: :unprocessable_content
    end

    result = ChutneyAnalyser.new(
      content:,
      filename: params[:filename],
      enabled_rules:,
      rule_options: normalization.options
    ).call
    render json: {
      issues: result.issues,
      valid: result.issues.empty?,
      parse_error: result.parse_error.present?,
      duration_ms: result.duration_ms,
      chutney_version: Chutney::VERSION
    }
  end
end
