class ChutneyRuleCatalog
  Setting = Data.define(:key, :label, :type, :default, :placeholder, :help, :min, :max) do
    def input_value(value = default)
      case type
      when :list
        Array(value).join(', ')
      when :groups
        Array(value).map { Array(it).join(', ') }.join("\n")
      else
        value.to_s
      end
    end

    def normalize(value)
      case type
      when :integer
        normalize_integer(value)
      when :list
        [ normalize_list(value), nil ]
      when :groups
        [ normalize_groups(value), nil ]
      when :pattern
        normalize_pattern(value)
      else
        [ value.to_s, nil ]
      end
    end

    private

    def normalize_integer(value)
      number = Integer(value, exception: false)
      return [ nil, "#{label} must be a whole number." ] unless number
      return [ nil, "#{label} must be between #{min} and #{max}." ] unless number.between?(min, max)

      [ number, nil ]
    end

    def normalize_list(value)
      values = value.is_a?(Array) ? value : value.to_s.split(/[\n,]/)
      values.map { it.to_s.strip.delete_prefix('@') }.reject(&:blank?).uniq.first(50)
    end

    def normalize_groups(value)
      groups = value.is_a?(Array) ? value : value.to_s.lines.map { it.split(',') }
      groups.map { normalize_list(it).first(20) }.select { it.size >= 2 }.first(20)
    end

    def normalize_pattern(value)
      pattern = value.to_s.strip.first(200)
      Regexp.new(pattern) if pattern.present?
      [ pattern, nil ]
    rescue RegexpError => error
      [ nil, "#{label} is not a valid regular expression: #{error.message}" ]
    end
  end

  Rule = Data.define(:name, :title, :summary, :category, :enabled_by_default, :documentation_url, :settings)
  Normalization = Data.define(:options, :errors)

  OPTION_DEFINITIONS = {
    'AvoidMutuallyExclusiveTags' => [
      { key: 'TagGroups', label: 'Exclusive tag groups', type: :groups, default: [], placeholder: "mobile, desktop\nen, fr, de", help: 'One comma-separated group per line. Tags within a line cannot appear together.', min: nil, max: nil }
    ],
    'AvoidTags' => [
      { key: 'Tags', label: 'Tags to avoid', type: :list, default: [], placeholder: 'focus, debug, wip', help: 'Comma-separated tags that should never be committed.', min: nil, max: nil }
    ],
    'RequiredTagsStartsWith' => [
      { key: 'Matcher', label: 'Allowed tag prefixes', type: :list, default: [], placeholder: 'JIRA, PROJECT', help: 'Comma-separated prefixes checked whenever tags are present.', min: nil, max: nil }
    ],
    'ScenarioNamesMatch' => [
      { key: 'Matcher', label: 'Scenario name pattern', type: :pattern, default: '', placeholder: '^AC-[0-9]+', help: 'A regular expression that every scenario name must match.', min: nil, max: nil }
    ],
    'TooLongStep' => [
      { key: 'MaxLength', label: 'Maximum characters', type: :integer, default: 80, placeholder: '80', help: 'Warn when a step is longer than this limit.', min: 1, max: 1_000 }
    ],
    'TooManyDifferentTags' => [
      { key: 'MaxCount', label: 'Maximum different tags', type: :integer, default: 3, placeholder: '3', help: 'Limit distinct tag names across a feature.', min: 1, max: 100 }
    ],
    'TooManySteps' => [
      { key: 'MaxCount', label: 'Maximum steps', type: :integer, default: 10, placeholder: '10', help: 'Warn when a scenario contains more steps.', min: 1, max: 100 }
    ],
    'TooManyTags' => [
      { key: 'MaxCount', label: 'Maximum tags', type: :integer, default: 3, placeholder: '3', help: 'Limit tags on a feature or scenario.', min: 1, max: 100 }
    ],
    'TooShortTag' => [
      { key: 'MinLength', label: 'Minimum characters', type: :integer, default: 2, placeholder: '2', help: 'Warn when a tag is shorter than this limit.', min: 1, max: 100 }
    ]
  }.freeze

  CATEGORY_ORDER = [
    'Names & language',
    'Scenarios & flow',
    'Tags & examples',
    'Structure & limits'
  ].freeze

  class << self
    def rules
      @rules ||= default_configuration.map do |name, configuration|
        documentation = RuleDocumentation.fetch(name)
        Rule.new(
          name:,
          title: documentation&.fetch(:title) || name.titleize,
          summary: summary_for(documentation),
          category: category_for(name),
          enabled_by_default: configuration.fetch('Enabled', false),
          documentation_url: RuleDocumentation.path_for(name),
          settings: settings_for(name, configuration)
        )
      end.sort_by { |rule| [ CATEGORY_ORDER.index(rule.category), rule.title ] }.freeze
    end

    def names
      @names ||= rules.map(&:name).freeze
    end

    def default_enabled_names
      @default_enabled_names ||= rules.select(&:enabled_by_default).map(&:name).freeze
    end

    def normalize_options(raw_options)
      source = {}
      source = raw_options.to_unsafe_h if raw_options.respond_to?(:to_unsafe_h)
      source = raw_options.to_h if source.empty? && raw_options.respond_to?(:to_h)
      errors = []
      options = rules.each_with_object({}) do |rule, normalized_rules|
        rule_source = source.fetch(rule.name, {})
        rule_source = rule_source.to_h if rule_source.respond_to?(:to_h)

        normalized = rule.settings.each_with_object({}) do |setting, values|
          next unless rule_source.key?(setting.key)

          value, error = setting.normalize(rule_source[setting.key])
          errors << "#{rule.title}: #{error}" if error
          values[setting.key] = value unless error
        end
        normalized_rules[rule.name] = normalized if normalized.any?
      end
      Normalization.new(options:, errors:)
    end

    private

    def default_configuration
      gem_root = Gem.loaded_specs.fetch('chutney').full_gem_path
      YAML.safe_load_file(File.join(gem_root, 'config', 'chutney_defaults.yml')).merge(
        'AvoidMutuallyExclusiveTags' => { 'Enabled' => false, 'TagGroups' => [] }
      )
    end

    def settings_for(name, configuration)
      OPTION_DEFINITIONS.fetch(name, []).map do |definition|
        Setting.new(**definition.merge(default: configuration.fetch(definition[:key], definition[:default])))
      end.freeze
    end

    def summary_for(documentation)
      paragraph = documentation&.fetch(:blocks)&.find { it[:type] == 'paragraph' }
      paragraph&.fetch(:content)&.truncate(180) || 'Configure whether Chutney runs this check.'
    end

    def category_for(name)
      case name
      when /Name|FullStop|Colon|Quoting|Typographer|Clumsy|LongStep|Comma/
        'Names & language'
      when /Scenario|Outline|Background|TestAction|Verification|StepFlow|Scripting|Splat|Givens|Use/
        'Scenarios & flow'
      when /Tag|Example|Variable/
        'Tags & examples'
      else
        'Structure & limits'
      end
    end
  end
end
