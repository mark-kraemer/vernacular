module Vernacular
  # What a checkpoint leaves behind in git: every gate verdict from every
  # round, the latest reviews, and a summary for the commit message. Held in
  # memory and written once at the end, so stashing a blocked checkpoint's
  # work never takes its evidence with it. Screenshots stay in tmp/vernacular.
  class Evidence
    attr_reader :dir, :rounds, :total_cost

    def initialize(screen, checkpoint_id)
      @dir = HOME.join('evidence', screen, checkpoint_id)
      @rounds = []
      @files = {}
      @total_cost = 0.0
    end

    def record(round, verdict)
      @rounds << { round:, gate: verdict.gate, passed: verdict.passed, at: Time.now.utc.iso8601,
                   detail: verdict.passed ? verdict.detail : verdict.feedback }
    end

    def cost(amount)
      @total_cost += amount
    end

    def save(name, payload)
      @files[name] = payload.is_a?(String) ? payload : JSON.pretty_generate(payload) + "\n"
    end

    def findings
      rounds.reject { it[:passed] }.map { "#{it[:gate]} (round #{it[:round]}): #{it[:detail].to_s[0, 3000]}" }
    end

    def write
      FileUtils.mkdir_p(dir)
      @files.merge('gates.json' => JSON.pretty_generate(rounds) + "\n").each { |name, body| File.write(dir.join(name), body) }
    end

    def summary
      passes = rounds.select { it[:passed] }.group_by { it[:gate] }.transform_values { it.last[:detail] }
      lines = passes.map { |gate, detail| "- #{gate}: #{detail}" }
      [ *lines, "- rounds: #{rounds.map { it[:round] }.max || 0}, failed gate runs: #{rounds.count { !it[:passed] }}",
       "- model cost: $#{format('%.2f', total_cost)}" ].join("\n")
    end
  end
end
