class RuleDocumentation
  SLUG_OVERRIDES = {
    'AvoidFullStop' => 'avoid-full-stops',
    'InvalidFileName' => 'invalid_file_name',
    'MissingVerification' => 'missing-test-verification',
    'RequiredTagsStartsWith' => 'required-tag-starts-with',
    'TooShortTag' => 'too_short_tag'
  }.freeze

  def self.path_for(rule)
    "/rules/#{rule}" if available?(rule)
  end

  def self.external_url_for(rule)
    "https://www.usechutney.com/docs/rules/#{slug_for(rule)}" if available?(rule)
  end

  def self.available?(rule)
    rule.to_s.match?(/\A[A-Z][A-Za-z]+\z/) && File.file?(source_path(rule))
  end

  def self.fetch(rule)
    return unless available?(rule)

    new(rule, File.read(source_path(rule))).to_h
  end

  def self.slug_for(rule)
    SLUG_OVERRIDES.fetch(rule.to_s) do
      rule.to_s.gsub(/([a-z\d])([A-Z])/, '\1-\2').downcase
    end
  end

  def self.source_path(rule)
    gem_root = Gem.loaded_specs.fetch('chutney').full_gem_path
    File.join(gem_root, 'usechutney.com.site/site/src/docs/rules', "#{slug_for(rule)}.page.md")
  end

  def initialize(rule, markdown)
    @rule = rule
    @lines = markdown.lines.map(&:chomp)
  end

  def to_h
    {
      rule: @rule,
      title: title,
      blocks: blocks,
      external_url: self.class.external_url_for(@rule)
    }
  end

  private

  def title
    @lines.find { it.start_with?('# ') }&.delete_prefix('# ') || @rule
  end

  def blocks
    result = []
    index = 0

    while index < @lines.length
      line = @lines[index]
      case line
      when /^# /, '', '{: .notice}'
        index += 1
      when /^## (.+)$/
        result << { type: 'heading', content: Regexp.last_match(1) }
        index += 1
      when /^```(\w*)$/
        language = Regexp.last_match(1).presence || 'text'
        code = []
        index += 1
        while index < @lines.length && !@lines[index].start_with?('```')
          code << @lines[index]
          index += 1
        end
        result << { type: 'code', language:, content: code.join("\n") }
        index += 1
      else
        paragraph = []
        while index < @lines.length && paragraph_line?(@lines[index])
          paragraph << @lines[index].gsub('<br/>', "\n")
          index += 1
        end
        result << { type: 'paragraph', content: paragraph.join(' ').gsub(/`([^`]+)`/, '\1') }
      end
    end

    result
  end

  def paragraph_line?(line)
    line.present? && !line.start_with?('#', '```', '{: .notice}')
  end
end
