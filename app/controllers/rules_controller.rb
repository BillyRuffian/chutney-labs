class RulesController < ApplicationController
  def show
    documentation = RuleDocumentation.fetch(params[:rule])
    return render json: { error: 'Rule documentation was not found.' }, status: :not_found unless documentation

    render json: documentation
  end
end
