module Vernacular
  # Both halves of a UI comparison, produced by the project's own commands:
  #
  #   capture_reference  VERNACULAR_SCENARIOS=a,b  → tmp/vernacular/reference/<scenario>/<state>.png
  #   capture_target     VERNACULAR_STATES=a:x,b:y → tmp/vernacular/target/<scenario>/<state>.png
  #
  # VERNACULAR_OUTPUT names the directory each command writes under.
  module Capture
    Pair = Data.define(:scenario, :state, :reference, :target)

    def self.reference_png(scenario, state) = TMP.join('reference', scenario, "#{state}.png")
    def self.target_png(scenario, state) = TMP.join('target', scenario, "#{state}.png")

    def self.reference(scenarios)
      Shell.sh(Vernacular.config.command('capture_reference'),
               env: { 'VERNACULAR_SCENARIOS' => scenarios.join(','), 'VERNACULAR_OUTPUT' => TMP.join('reference').to_s })
    end

    # Returns [result, pairs]; a pair's target is nil when no PNG was written.
    def self.target(states)
      specs = states.map { it.split(':', 2) }
      specs.each { FileUtils.rm_f(target_png(*it)) }
      result = Shell.sh(Vernacular.config.command('capture_target'),
                        env: { 'VERNACULAR_STATES' => states.join(','), 'VERNACULAR_OUTPUT' => TMP.join('target').to_s })
      pairs = specs.map do |scenario, state|
        png = target_png(scenario, state)
        Pair.new(scenario, state, reference_png(scenario, state), png.exist? ? png : nil)
      end
      [ result, pairs ]
    end

    # `shoot library` means every state the last reference capture produced.
    def self.expand(args)
      args.flat_map do |arg|
        next [ arg ] if arg.include?(':')

        Dir[TMP.join('reference', arg, '*.png').to_s].sort.map { "#{arg}:#{File.basename(it, '.png')}" }
      end
    end
  end
end
