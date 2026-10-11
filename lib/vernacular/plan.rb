module Vernacular
  # vernacular/screens/<screen>/plan.yml, written by the planner (or by hand).
  # The driver checks its shape before anything is built — the stand-in for
  # an engineer approving the checkpoint plan.
  class Plan
    Checkpoint = Data.define(:id, :title, :goal, :ui, :scope, :states, :tests) do
      def scenarios = states.map { it.split(':').first }.uniq
    end

    def self.path(screen) = HOME.join('screens', screen, 'plan.yml')

    def self.load(screen)
      new(screen, YAML.load_file(path(screen)) || {})
    end

    attr_reader :screen, :checkpoints

    def initialize(screen, data)
      @screen = screen
      @checkpoints = Array(data['checkpoints']).map do |c|
        Checkpoint.new(
          id: c['id'].to_s, title: c['title'].to_s, goal: c['goal'].to_s, ui: c['ui'] != false,
          scope: c['scope'].to_s, states: Array(c['states']).map(&:to_s), tests: Array(c['tests']).map(&:to_s)
        )
      end
    end

    def problems
      issues = []
      issues << 'no checkpoints' if checkpoints.empty?
      ids = checkpoints.map(&:id)
      issues << "duplicate checkpoint ids: #{ids.tally.select { _2 > 1 }.keys.join(', ')}" if ids.uniq.size != ids.size
      checkpoints.each do |c|
        issues << "#{c.id}: id must look like 01-short-slug" unless c.id.match?(/\A\d{2}-[a-z0-9-]+\z/)
        issues << "#{c.id}: missing goal" if c.goal.strip.empty?
        issues << "#{c.id}: ui checkpoint needs scope and states" if c.ui && (c.scope.strip.empty? || c.states.empty?)
        issues << "#{c.id}: no tests" if c.tests.empty?
        issues << "#{c.id}: blank test name" if c.tests.any? { it.strip.empty? }
        c.states.each do |state|
          issues << "#{c.id}: state #{state.inspect} must be scenario:state" unless state.match?(/\A\w+:\w+\z/)
        end
      end
      issues
    end
  end
end
