module Vernacular
  # The machine gates, in order. Each returns a Verdict; `feedback` is what
  # the implementer is told when it fails. The model never grades itself:
  # build and test gates read exit codes and test output, and the review
  # gates use fresh, read-only reviewers.
  module Gates
    Verdict = Data.define(:gate, :passed, :feedback, :detail)

    def self.config = Vernacular.config

    def self.changed_files
      Shell.run('git', 'status', '--porcelain', '--untracked-files=all').output.lines.map { it[3..].strip.split(' -> ').last }
    end

    def self.build
      config.lint.each do |lint|
        files = changed_files.select { File.fnmatch?(lint[:files], it, File::FNM_EXTGLOB) && ROOT.join(it).file? }
        next if files.empty?

        result = Shell.sh("#{lint[:run]} #{files.shelljoin}")
        return Verdict.new('build', false, "#{lint[:run]} failed:\n#{result.tail}", result.tail) unless result.success?
      end

      found = Checks.violations(Checks.committed, changed_files)
      if found.any?
        report = Checks.report(found)
        return Verdict.new('build', false, "Vernacular checks failed (vernacular/checks/*.yml, read from the last commit):\n#{report}", report)
      end

      config.commands('build').each do |line|
        result = Shell.sh(line)
        return Verdict.new('build', false, "`#{line}` failed:\n#{errors(result)}", result.tail) unless result.success?
      end

      Verdict.new('build', true, nil, [ *config.lint.map { it[:run] }, 'checks', *config.commands('build') ].join(', '))
    end

    def self.behavior(checkpoint)
      output = +''
      config.commands('test').each do |line|
        result = Shell.sh(line)
        output << result.output
        return Verdict.new('behavior', false, "`#{line}` failed:\n#{result.tail(150)}", result.tail) unless result.success?
      end

      missing = checkpoint.tests.reject { passed?(output, it) }
      if missing.any?
        return Verdict.new('behavior', false, "These planned tests did not run and pass: #{missing.join(', ')}\n" \
                                              "Test output:\n#{output.lines.last(150).join}", missing)
      end

      Verdict.new('behavior', true, nil, "#{checkpoint.tests.size} planned tests passed; #{config.commands('test').join(', ')}")
    end

    # With commands.test_passed ('Test {name}\(.*?\) passed'), a name only
    # counts when the runner reports it passed; without it, when it appears.
    def self.passed?(output, name)
      pattern = config.test_passed
      pattern ? output.match?(Regexp.new(pattern.gsub('{name}', Regexp.escape(name)))) : output.include?(name)
    end

    UI_SCHEMA = {
      type: 'object', required: %w[comparisons],
      properties: {
        comparisons: {
          type: 'array',
          items: {
            type: 'object', required: %w[state verdict differences],
            properties: {
              state: { type: 'string' },
              verdict: { type: 'string', enum: %w[PASS FAIL INVALID] },
              invalid_reason: { type: 'string' },
              differences: {
                type: 'array',
                items: {
                  type: 'object', required: %w[severity location description fixable],
                  properties: {
                    severity: { type: 'string', enum: %w[high medium low] },
                    location: { type: 'string' }, description: { type: 'string' }, fixable: { type: 'boolean' }
                  }
                }
              }
            }
          }
        }
      }
    }.freeze

    def self.ui(checkpoint, evidence)
      return Verdict.new('ui', false, 'commands.capture_reference and commands.capture_target are required for ui checkpoints', nil) unless config.captures?

      capture = Capture.reference(checkpoint.scenarios)
      return Verdict.new('ui', false, "Reference capture failed:\n#{capture.tail}", capture.tail) unless capture.success?

      2.times do |attempt|
        result, pairs = Capture.target(checkpoint.states)
        return Verdict.new('ui', false, "Target capture failed:\n#{errors(result)}", result.tail) unless result.success?

        unshot = pairs.reject(&:target)
        return Verdict.new('ui', false, "Could not capture #{unshot.map { "#{it.scenario}:#{it.state}" }.join(', ')}", nil) if unshot.any?

        reply = Claude.review(Prompts.ui_review(checkpoint, pairs), schema: UI_SCHEMA)
        evidence.cost(reply.cost)
        return Verdict.new('ui', false, "The UI reviewer errored; try again:\n#{reply.raw}", reply.raw) unless reply.structured

        review = reply.structured
        evidence.save('ui_review.json', review)
        comparisons = review['comparisons']
        next if attempt.zero? && comparisons.any? { it['verdict'] == 'INVALID' }

        blocking = comparisons.flat_map do |c|
          invalid = c['verdict'] == 'INVALID' ? [ { 'severity' => 'high', 'location' => 'whole screen', 'fixable' => true,
                                                   'description' => "Not the same state as the reference: #{c['invalid_reason']}" } ] : []
          (invalid + c['differences'].select { it['fixable'] }).map { it.merge('state' => c['state']) }
        end
        blocking += comparisons.select { it['verdict'] == 'FAIL' && it['differences'].none? { |d| d['fixable'] } }
                               .map { { 'state' => it['state'], 'severity' => 'high', 'location' => 'screen', 'description' => 'Reviewer failed this state without a fixable difference listed; compare the screenshots yourself.' } }
        return Verdict.new('ui', true, nil, "#{comparisons.size} states match") if blocking.empty?

        lines = blocking.map { "- [#{it['severity']}] #{it['state']} — #{it['location']}: #{it['description']}" }
        shots = pairs.map { "#{it.scenario}:#{it.state} reference #{it.reference} · target #{it.target}" }
        return Verdict.new('ui', false,
                           "The UI reviewer found differences between the reference and the target:\n#{lines.join("\n")}\n\nScreenshots:\n#{shots.join("\n")}",
                           blocking)
      end
    end

    REVIEW_SCHEMA = {
      type: 'object', required: %w[verdict findings],
      properties: {
        verdict: { type: 'string', enum: %w[APPROVE CHANGES] },
        findings: {
          type: 'array',
          items: {
            type: 'object', required: %w[file problem fix],
            properties: { file: { type: 'string' }, line: { type: 'integer' }, rule: { type: 'string' },
                          problem: { type: 'string' }, fix: { type: 'string' } }
          }
        }
      }
    }.freeze

    def self.adversarial(screen, checkpoint, evidence)
      Shell.run('git', 'add', '--intent-to-add', '--all')
      diff = TMP.join('runs', screen, checkpoint.id, 'diff.patch')
      FileUtils.mkdir_p(diff.dirname)
      File.write(diff, Shell.run('git', 'diff', 'HEAD').output)

      prior = evidence.rounds.select { it[:gate] == 'adversarial' && !it[:passed] }.map { it[:detail].to_s }
      reviews = config.reviewers.keys.map do |name|
        Thread.new { [ name, Claude.review(Prompts.review(name, screen, checkpoint, diff, prior), schema: REVIEW_SCHEMA) ] }
      end.map(&:value)

      findings = reviews.flat_map do |name, reply|
        evidence.cost(reply.cost)
        next [ { 'reviewer' => name, 'file' => '-', 'problem' => "#{name} reviewer errored: #{reply.raw}", 'fix' => 'none; rerun' } ] unless reply.structured

        evidence.save("#{name}_review.json", reply.structured)
        verdict = reply.structured
        list = verdict['findings'].map { it.merge('reviewer' => name) }
        next list unless list.empty? && verdict['verdict'] == 'CHANGES'

        [ { 'reviewer' => name, 'file' => '-', 'problem' => 'Reviewer returned CHANGES without findings', 'fix' => 'none' } ]
      end
      return Verdict.new('adversarial', true, nil, reviews.map { "#{it[0]} APPROVE" }.join(' · ')) if findings.empty?

      lines = findings.map { "- (#{it['reviewer']}#{" rule #{it['rule']}" if it['rule']}) #{it['file']}#{":#{it['line']}" if it['line']}: #{it['problem']} → #{it['fix']}" }
      Verdict.new('adversarial', false, "The adversarial reviewers want changes. Fix every one:\n#{lines.join("\n")}", findings)
    end

    def self.final
      config.commands('regression').each do |line|
        result = Shell.sh(line)
        return Verdict.new('final', false, "Regression `#{line}` failed:\n#{result.tail(150)}", result.tail) unless result.success?
      end
      Verdict.new('final', true, nil, config.commands('regression').join(', ').then { it.empty? ? 'no regression commands' : it })
    end

    # Changes under `visible:` since the UI gate last passed mean a re-review.
    def self.visible_fingerprint
      Shell.run('git', 'add', '--intent-to-add', '--all')
      Digest::SHA256.hexdigest(Shell.run('git', 'diff', 'HEAD', '--', *config.visible).output)
    end

    def self.errors(result)
      lines = result.output.lines.grep(/error:|warning: unreachable|fatal/).uniq.first(40)
      lines.any? ? lines.join : result.tail
    end
  end
end
