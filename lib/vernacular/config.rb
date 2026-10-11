module Vernacular
  # vernacular/config.yml: everything about the project's stacks. The loop
  # itself knows nothing about any language, framework, or platform.
  class Config
    PATH = HOME.join('config.yml')

    DEFAULT_REVIEWERS = {
      'architecture' => { 'docs' => [], 'focus' => 'bugs, unhandled errors, security holes, state that can desync, ' \
                                                   'tests that do not test what they are named for' },
      'guidelines' => { 'docs' => [], 'focus' => 'the design system, platform conventions, accessibility, copy that matches the reference' }
    }.freeze

    def self.load(path = PATH)
      new(path.exist? ? YAML.safe_load(path.read) || {} : {})
    end

    def initialize(data)
      @data = data
    end

    def reference = @data['reference'].to_s
    def target = @data['target'].to_s
    def read_first = Array(@data['read_first']).map(&:to_s)
    def hard_limits = @data['hard_limits'].to_s.strip
    def planning = @data['planning'].to_s.strip
    def ui_expected = @data['ui_expected'].to_s.strip
    def tools = Array(@data['tools']).map(&:to_s)
    def visible = Array(@data.fetch('visible', [ '.' ])).map(&:to_s)
    def commit_trailer = @data.fetch('commit_trailer', 'Co-Authored-By: Claude <noreply@anthropic.com>').to_s

    def scenarios(screen)
      @data['scenarios']&.gsub('{screen}', screen)
    end

    def build_model = ENV.fetch('VERNACULAR_MODEL') { @data.dig('models', 'build') || 'opus' }
    def review_model = ENV.fetch('VERNACULAR_REVIEW_MODEL') { @data.dig('models', 'review') || 'opus' }
    def max_rounds = Integer(ENV.fetch('VERNACULAR_MAX_ROUNDS') { @data.fetch('max_rounds', 8) })
    def command_timeout = Integer(@data.fetch('command_timeout', 3600))

    def commands(name) = Array(@data.dig('commands', name)).map(&:to_s)
    def command(name) = @data.dig('commands', name)&.to_s
    def test_passed = @data.dig('commands', 'test_passed')&.to_s
    def lint = Array(@data.dig('commands', 'lint')).map { { files: it['files'].to_s, run: it['run'].to_s } }
    def captures? = !command('capture_reference').nil? && !command('capture_target').nil?

    def reviewers
      (@data['reviewers'] || DEFAULT_REVIEWERS).to_h do |name, spec|
        [ name.to_s, { docs: Array(spec&.dig('docs')).map(&:to_s), focus: spec&.dig('focus').to_s } ]
      end
    end

    # What the reviewers enforce. A checkpoint that edits one of these
    # changes its own rules, so the driver records the diff for a human.
    def contract
      (reviewers.values.flat_map { it[:docs] } + [ 'vernacular/screens' ]).uniq
    end
  end
end
