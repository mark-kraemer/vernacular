module Vernacular
  # One checkpoint: implement, then gates in order; any failure goes back to
  # the same implementer session as a fix request. Every gate must pass in
  # the same round for the checkpoint to commit. Out of rounds → blocked.
  class CheckpointRun
    MEMORY_SCHEMA = { type: 'object', required: %w[memory], properties: { memory: { type: 'string' } } }.freeze

    def initialize(plan, checkpoint, resuming: false)
      @resuming = resuming
      @plan = plan
      @checkpoint = checkpoint
      @evidence = Evidence.new(plan.screen, checkpoint.id)
      @session_id = SecureRandom.uuid
      @ui_passed_at = nil
    end

    def run
      message = Prompts.implement(@plan, @checkpoint)
      if @resuming
        message += "\n\nAn earlier attempt at this checkpoint was interrupted before any gate ran. Its uncommitted work is " \
                   "still in the tree (`git status`, `git diff`). Review it critically, keep what is right, and finish the checkpoint.\n"
      end
      1.upto(max_rounds) do |round|
        Vernacular.log("#{tag} round #{round}: implementing")
        reply = Claude.build(message, session_id: @session_id, resume: round > 1)
        @evidence.cost(reply.cost)
        unless reply.ok
          Vernacular.log("#{tag} implementer errored: #{reply.raw.lines.last(3).join.strip}")
          message = 'Your previous turn ended with an error before finishing. Check the working tree and continue the checkpoint.'
          next
        end

        failure = gates(round)
        return commit(round) if failure.nil?

        Vernacular.log("#{tag} round #{round}: #{failure.gate} gate failed")
        message = Prompts.fix(@checkpoint, failure, round)
      end
      block
    end

    private

    def max_rounds = Vernacular.config.max_rounds

    def tag = "#{@plan.screen}/#{@checkpoint.id}"

    def gates(round)
      run_gate(round) { Gates.build } ||
        run_gate(round) { Gates.behavior(@checkpoint) } ||
        ui_gate(round) ||
        run_gate(round) { Gates.adversarial(@plan.screen, @checkpoint, @evidence) } ||
        ui_gate(round) ||
        run_gate(round) { Gates.final }
    end

    # Skipped for logic-only checkpoints, and when nothing that can change a
    # pixel has changed since the UI gate last passed.
    def ui_gate(round)
      return nil unless @checkpoint.ui
      return nil if @ui_passed_at == Gates.visible_fingerprint

      failure = run_gate(round) { Gates.ui(@checkpoint, @evidence) }
      @ui_passed_at = Gates.visible_fingerprint if failure.nil?
      failure
    end

    def run_gate(round)
      verdict = yield
      @evidence.record(round, verdict)
      unless verdict.passed
        log = TMP.join('runs', @plan.screen, @checkpoint.id, "round-#{round}-#{verdict.gate}.txt")
        FileUtils.mkdir_p(log.dirname)
        File.write(log, verdict.feedback.to_s)
      end
      Vernacular.log("#{tag}   #{verdict.gate}: #{verdict.passed ? 'pass' : 'FAIL'}")
      verdict.passed ? nil : verdict
    end

    def commit(round)
      amended = record_decisions
      curate_memory
      Improvement.new(@plan, @checkpoint, @evidence).apply
      @evidence.write
      Shell.run('git', 'add', '--all')
      message = "vernacular(#{@plan.screen}): #{'[contract] ' if amended}#{@checkpoint.id} #{@checkpoint.title}\n\n" \
                "#{@checkpoint.goal.strip.split(/\n\s*\n/).first}\n\n" \
                "Passed every gate in round #{round}.\n#{@evidence.summary}\n" \
                "Evidence: #{@evidence.dir.relative_path_from(ROOT)}/\n" \
                "#{"\n#{Vernacular.config.commit_trailer}\n" unless Vernacular.config.commit_trailer.empty?}"
      result = Shell.run('git', 'commit', '--no-verify', '-F', '-', stdin: message)
      Vernacular.log("#{tag} committed: #{Shell.run('git', 'rev-parse', '--short', 'HEAD').output.strip}") if result.success?
      result.success? ? :done : block("git commit failed: #{result.tail}")
    end

    # The reviewers enforce the contract docs and the plans, so a checkpoint
    # that rewrites them changes its own rules; a human reads each one later.
    def record_decisions
      paths = Vernacular.config.contract.select { ROOT.join(it).exist? }
      diff = paths.empty? ? '' : Shell.run('git', 'diff', 'HEAD', '--', *paths).output.strip
      return false if diff.empty?

      Ledger.decisions.append("#{tag} (#{Time.now.strftime('%Y-%m-%d')})", "```diff\n#{diff}\n```")
      Vernacular.log("#{tag}   contract changed; recorded in vernacular/decisions.md")
      true
    end

    def curate_memory
      reply = Claude.review(Prompts.memory(@plan.screen, @checkpoint, @evidence.findings), schema: MEMORY_SCHEMA)
      @evidence.cost(reply.cost)
      memory = reply.structured&.fetch('memory', nil)
      File.write(HOME.join('memory.md'), memory.strip + "\n") if memory && memory.length > 100
    end

    # The work is stashed, not discarded: `git stash list` shows it by name.
    def block(reason = "out of rounds (#{max_rounds})")
      Shell.run('git', 'reset', '--quiet')
      stash = Shell.run('git', 'stash', 'push', '--include-untracked', '-m', "vernacular blocked #{tag}")
      abort "vernacular: could not stash #{tag}; stopping so its work isn't swept into the next screen:\n#{stash.tail}" unless stash.success? && Gates.changed_files.empty?

      @evidence.save('blocked.md', "# Blocked: #{tag}\n\n#{reason}\n\nWork is in `git stash list` as \"vernacular blocked #{tag}\".\n\n" \
                                   "## Last failures\n\n#{@evidence.findings.last(3).join("\n\n")}\n")
      @evidence.write
      Vernacular.log("#{tag} BLOCKED: #{reason}")
      :blocked
    end
  end
end
