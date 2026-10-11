module Vernacular
  # Headless Claude Code. Builders may edit within an allowlist; reviewers are
  # read-only, start from a fresh context every time, and must answer in the
  # JSON shape their schema demands. Nothing here can commit or push.
  module Claude
    Reply = Data.define(:ok, :text, :structured, :session_id, :cost, :raw)

    READ_ONLY = %w[Read Glob Grep Bash(git\ diff:*) Bash(git\ show:*) Bash(git\ log:*) Bash(ls:*)].freeze

    BUILDER_TOOLS = %w[
      Read Edit Write Glob Grep
      Bash(vernacular\ capture:*) Bash(vernacular\ shoot:*)
      Bash(git\ diff:*) Bash(git\ status:*) Bash(git\ log:*) Bash(git\ show:*) Bash(git\ rm:*) Bash(git\ mv:*)
      Bash(ls:*) Bash(mkdir:*) Bash(cp:*) Bash(mv:*) Bash(find:*) Bash(grep:*) Bash(wc:*) Bash(head:*) Bash(tail:*)
    ].freeze

    DENIED = %w[Bash(git\ commit:*) Bash(git\ push:*) Bash(git\ reset:*) Bash(git\ checkout:*) Bash(git\ stash:*)
                Bash(rm:*) WebFetch WebSearch Agent].freeze

    def self.build(prompt, session_id:, resume: false, timeout: 3600)
      flags = resume ? [ '--resume', session_id ] : [ '--session-id', session_id ]
      invoke(prompt, *flags, '--model', Vernacular.config.build_model, '--permission-mode', 'acceptEdits',
             '--allowedTools', *BUILDER_TOOLS, *Vernacular.config.tools, '--disallowedTools', *DENIED, timeout:)
    end

    def self.plan(prompt, session_id:, resume: false, writable:, timeout: 3600)
      flags = resume ? [ '--resume', session_id ] : [ '--session-id', session_id ]
      writes = writable.flat_map { [ "Edit(#{it})", "Write(#{it})" ] }
      invoke(prompt, *flags, '--model', Vernacular.config.build_model, '--permission-mode', 'default',
             '--allowedTools', *READ_ONLY, 'Bash(vernacular\ capture:*)', *writes,
             '--disallowedTools', *DENIED, timeout:)
    end

    def self.review(prompt, schema:, timeout: 1800)
      invoke(prompt, '--model', Vernacular.config.review_model, '--permission-mode', 'default', '--no-session-persistence',
             '--allowedTools', *READ_ONLY, '--disallowedTools', *DENIED, 'Edit', 'Write',
             '--json-schema', JSON.generate(schema), timeout:)
    end

    UNAVAILABLE = /hit your (?:session |usage |weekly )?limit|usage limit|rate.limit|overloaded/i
    LIMIT_WAIT = Integer(ENV.fetch('VERNACULAR_LIMIT_WAIT', 600))

    # A usage limit is the account pausing, not the model failing: wait it
    # out and retry the same call, so it never costs a round or blocks a
    # screen. A new session that already started is resumed, not recreated.
    def self.invoke(prompt, *flags, timeout:)
      loop do
        reply = attempt(prompt, *flags, timeout:)
        return reply unless !reply.ok && "#{reply.text} #{reply.raw}".match?(UNAVAILABLE)

        Vernacular.log("claude unavailable (#{reply.text[0, 100]}); retrying in #{LIMIT_WAIT}s")
        sleep LIMIT_WAIT
        flags = resumable(flags)
      end
    end

    def self.resumable(flags)
      index = flags.index('--session-id')
      return flags unless index && transcript(flags[index + 1]).exist?

      flags.dup.tap { it[index] = '--resume' }
    end

    def self.transcript(session_id)
      Pathname(Dir.home).join('.claude/projects', ROOT.to_s.gsub(/[^A-Za-z0-9]/, '-'), "#{session_id}.jsonl")
    end

    def self.attempt(prompt, *flags, timeout:)
      result = Shell.run('claude', '-p', '--output-format', 'json', *flags, stdin: prompt, timeout:)
      data = JSON.parse(result.output[/\{.*\}/m] || '{}')
      Reply.new(
        ok: result.success? && !data['is_error'],
        text: data['result'].to_s,
        structured: data['structured_output'],
        session_id: data['session_id'],
        cost: data['total_cost_usd'].to_f,
        raw: result.success? ? '' : result.tail(40)
      )
    rescue JSON::ParserError
      Reply.new(ok: false, text: '', structured: nil, session_id: nil, cost: 0.0, raw: result.tail(40))
    end
  end
end
