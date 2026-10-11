module Vernacular
  # Prompt templates live in the gem's prompts/; a file of the same name in
  # vernacular/prompts/ replaces the default. Every template can use the
  # project-wide placeholders from config.yml.
  module Prompts
    def self.template(*names)
      names.each do |name|
        [ HOME.join('prompts', "#{name}.md"), GEM.join('prompts', "#{name}.md") ].each { return it.read if it.exist? }
      end
      raise ArgumentError, "no prompt template named #{names.join(' or ')}"
    end

    def self.fill(names, **vars)
      config = Vernacular.config
      shared = { reference: config.reference, target: config.target, read_first: bullets(config.read_first),
                 hard_limits: config.hard_limits.empty? ? '(none beyond the goal)' : config.hard_limits }
      shared.merge(vars).reduce(template(*Array(names))) { |text, (key, value)| text.gsub("{{#{key}}}", value.to_s) }
    end

    def self.plan(entry)
      config = Vernacular.config
      scenarios = config.scenarios(entry['screen'])
      fill('planner', screen: entry['screen'], notes: entry['notes'], reference_files: list(Array(entry['reference'])),
                      planning: config.planning.empty? ? '' : "Project notes for planning:\n#{config.planning}\n",
                      scenarios: scenarios ? "`#{scenarios}`, which seeds the data and defines every state your plan lists" : '(none configured)')
    end

    def self.implement(plan, checkpoint)
      config = Vernacular.config
      position = "#{plan.checkpoints.index(checkpoint) + 1} of #{plan.checkpoints.size}"
      commands = %w[build test].flat_map { config.commands(it) }
      fill('implementer', screen: plan.screen, checkpoint_id: checkpoint.id, title: checkpoint.title, position:,
                          goal: checkpoint.goal, scope: checkpoint.ui ? checkpoint.scope : '(logic-only; no UI gate)',
                          states: list(checkpoint.states), tests: list(checkpoint.tests),
                          reviewers: bullets(config.reviewers.map { |name, spec| "#{name}: #{[ *spec[:docs], spec[:focus] ].reject(&:empty?).join('; ')}" }),
                          commands: bullets(commands.map { "`#{it}`" }))
    end

    def self.fix(checkpoint, verdict, round)
      fill('fix', gate: verdict.gate, round:, max_rounds: Vernacular.config.max_rounds, checkpoint_id: checkpoint.id,
                  feedback: verdict.feedback)
    end

    def self.ui_review(checkpoint, pairs)
      lines = pairs.map { "- #{it.scenario}:#{it.state}\n  reference: #{it.reference}\n  target: #{it.target}" }
      expected = Vernacular.config.ui_expected
      fill('ui_reviewer', checkpoint_id: checkpoint.id, title: checkpoint.title, scope: checkpoint.scope, pairs: lines.join("\n"),
                          ui_expected: expected.empty? ? '' : "#{expected}\n")
    end

    def self.review(name, screen, checkpoint, diff, prior = [])
      spec = Vernacular.config.reviewers.fetch(name)
      fill([ "#{name}_reviewer", 'reviewer' ],
           reviewer: name, screen:, checkpoint_id: checkpoint.id, title: checkpoint.title, goal: checkpoint.goal,
           diff:, states: list(checkpoint.states), docs: spec[:docs].empty? ? '- (no documents configured)' : bullets(spec[:docs]),
           focus: spec[:focus], prior: prior.empty? ? '(none — this is the first review round)' : prior.join("\n\n"))
    end

    def self.memory(screen, checkpoint, findings)
      fill('memory_curator', screen:, checkpoint_id: checkpoint.id, memory: current_memory,
                             findings: findings.empty? ? '(none — every gate passed first time)' : findings.join("\n\n"))
    end

    def self.improve(screen, checkpoint, evidence, checks)
      existing = checks.map { "- #{it.name} (#{it.paths.join(', ')}): /#{it.pattern}/ — #{it.why}" }
      fill('improver', screen:, checkpoint_id: checkpoint.id, findings: evidence.findings.join("\n\n"),
                       rounds: evidence.rounds.map { it[:round] }.max, memory: current_memory,
                       checks: existing.empty? ? '(none yet)' : existing.join("\n"))
    end

    def self.current_memory
      path = HOME.join('memory.md')
      path.exist? ? path.read : ''
    end

    def self.list(items)
      items.empty? ? '(none)' : items.join(', ')
    end

    def self.bullets(items)
      items.empty? ? '- (none)' : items.map { "- #{it}" }.join("\n")
    end
  end
end
