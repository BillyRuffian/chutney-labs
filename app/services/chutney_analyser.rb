require 'tmpdir'

class ChutneyAnalyser
  Result = Data.define(:issues, :parse_error, :duration_ms)
  ANALYSIS_LOCK = Mutex.new
  EXPECTED_GHERKIN = {
    '#Language' => 'a language header',
    '#TagLine' => 'a tag',
    '#FeatureLine' => 'a Feature: declaration',
    '#RuleLine' => 'a Rule: declaration',
    '#BackgroundLine' => 'a Background: declaration',
    '#ScenarioLine' => 'a Scenario: declaration',
    '#ExamplesLine' => 'an Examples: declaration',
    '#StepLine' => 'a Given, When, Then, And, or But step',
    '#TableRow' => 'a pipe-delimited table row',
    '#DocStringSeparator' => 'a doc string delimiter',
    '#Comment' => 'a comment',
    '#Empty' => 'a blank line',
    '#EOF' => 'the end of the file'
  }.freeze

  def initialize(content:, filename:, enabled_rules: nil, rule_options: {})
    @content = content.to_s
    @filename = safe_filename(filename)
    @enabled_rules = enabled_rules&.intersection(ChutneyRuleCatalog.names)
    @rule_options = rule_options.slice(*ChutneyRuleCatalog.names)
  end

  def call
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    issues = []
    parse_error = nil

    Dir.mktmpdir('chutney-online-') do |directory|
      path = File.join(directory, @filename)
      File.write(path, @content)

      issues = analyse_in_isolation(path)
    rescue StandardError => error
      parse_error = parser_issue(error)
      issues = [ parse_error ]
    end

    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round
    Result.new(issues:, parse_error:, duration_ms: elapsed)
  end

  private

  def safe_filename(filename)
    value = File.basename(filename.to_s).gsub(/[^\w.-]/, '-')
    value = 'untitled.feature' if value.blank?
    value.end_with?('.feature') ? value : "#{value}.feature"
  end

  # Some cross-file Chutney rules retain their indexes at class level. That is
  # useful for one CLI run over many files, but web requests are independent.
  # Serialize access so concurrent requests cannot repopulate another request's
  # cache between the reset and analysis steps.
  def analyse_in_isolation(path)
    ANALYSIS_LOCK.synchronize do
      reset_global_linter_state

      begin
        linter = Chutney::ChutneyLint.new(path)
        linter.configuration.quiet!
        apply_rule_selection(linter.configuration) if @enabled_rules
        flatten(linter.analyse.fetch(path, []))
      ensure
        reset_global_linter_state
      end
    end
  end

  def reset_global_linter_state
    Chutney::SameScenario.reset
    Chutney::SameTagDifferentCase.class_variable_set(:@@all_known_tags, [])
  end

  def apply_rule_selection(configuration)
    ChutneyRuleCatalog.names.each do |rule|
      configuration[rule] ||= {}
      configuration[rule]['Enabled'] = rule_enabled?(rule)
      @rule_options.fetch(rule, {}).each do |key, value|
        configuration[rule][key] = value
      end
    end
  end

  def rule_enabled?(rule)
    return false unless @enabled_rules.include?(rule)
    return feature_contains_tags? if rule == 'RequiredTagsStartsWith'

    true
  end

  def feature_contains_tags?
    @feature_contains_tags ||= @content.match?(/^\s*@\S+/)
  end

  def flatten(groups)
    groups.flat_map do |group|
      group.fetch(:issues, []).map do |issue|
        location = issue[:location] || {}
        {
          rule: group[:linter],
          message: issue[:message],
          line: location[:line] || 1,
          column: location[:column] || 1,
          type: issue[:gherkin_type] || 'feature',
          severity: 'warning',
          documentation_url: RuleDocumentation.path_for(group[:linter])
        }
      end
    end.sort_by { |issue| [ issue[:line], issue[:column], issue[:rule] ] }
  end

  def parser_issue(error)
    detail = original_message(error)
    parser_match = detail.match(/\((\d+):(\d+)\):\s*expected:\s*(.+?),\s*got\s+'([^'\n]*)'/)
    return structured_parser_issue(parser_match) if parser_match

    examples_issue || generic_parser_issue
  end

  def original_message(error)
    message = error.respond_to?(:original_message) ? error.original_message : error.message
    message.to_s.sub(/\ARuntimeError - /, '')
  end

  def structured_parser_issue(match)
    line = match[1].to_i
    column = match[2].to_i
    expected = match[3].scan(/#\w+/).filter_map { EXPECTED_GHERKIN[it] }.uniq.first(4)
    found = match[4]
    suggestion = missing_colon_suggestion(found)

    message = "Invalid Gherkin at line #{line}, column #{column}."
    message += " Expected #{expected.to_sentence(last_word_connector: ', or ')}, but found “#{found}”." if expected.any?
    message += " #{suggestion || 'Check the keyword, colon, and indentation on this line.'}"

    {
      rule: 'GherkinSyntax', message:, line:, column:,
      type: 'syntax',
      severity: 'error'
    }
  end

  def missing_colon_suggestion(found)
    match = found.match(/\A\s*(Feature|Rule|Background|Scenario Outline|Scenario|Examples)\s+(.+)\z/i)
    return unless match

    "Add the missing colon: “#{match[1]}: #{match[2]}”."
  end

  def examples_issue
    lines = @content.lines
    index = lines.each_index.find do |line_index|
      line = lines[line_index]
      next false unless line.match?(/^\s*Examples\s*:/i)

      following_line = lines[(line_index + 1)..]&.find { !it.strip.empty? }
      following_line.nil? || !following_line.match?(/^\s*\|/)
    end
    return unless index

    line = index + 1
    {
      rule: 'GherkinSyntax',
      message: "Invalid Examples block at line #{line}. Add a pipe-delimited header and at least one data row, such as “| user |” followed by “| bob |” below Examples:.",
      line:,
      column: 1,
      type: 'syntax',
      severity: 'error'
    }
  end

  def generic_parser_issue
    {
      rule: 'GherkinSyntax',
      message: 'Chutney could not analyse this Gherkin file. Check that Feature, Scenario, Background, and Examples lines use a colon; steps are nested inside a scenario; and example data uses pipe-delimited tables.',
      line: 1,
      column: 1,
      type: 'syntax',
      severity: 'error'
    }
  end
end
