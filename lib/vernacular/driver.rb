module Vernacular
  class Driver
    PLAN_ATTEMPTS = 3

    def run(names)
      require_setup!
      claim_run!
      queue = Queue.load
      @interrupted = queue.screens.find { it['status'] == 'running' }&.fetch('screen')
      unless @interrupted
        require_clean_tree!
        require_green_baseline!
      end
      targets = names.empty? ? queue.pending.map { it['screen'] } : names
      targets = [ @interrupted, *targets ].uniq if @interrupted && (names.empty? || names.include?(@interrupted))
      abort "vernacular: #{@interrupted} was interrupted mid-checkpoint; run it first (vernacular run #{@interrupted})" if @interrupted && targets.first != @interrupted
      targets.each do |screen|
        status = run_screen(queue, screen)
        Vernacular.log("#{screen}: #{status}")
        break if status == 'paused'
      end
      status_report
    end

    def pause
      FileUtils.mkdir_p(TMP)
      FileUtils.touch(PAUSE)
      puts running_pid ? 'vernacular: pausing after the current checkpoint commits' : 'vernacular: not running; nothing to pause'
      PAUSE.delete unless running_pid
    end

    def plan(screen)
      require_setup!
      require_clean_tree!
      plan_screen(Queue.load, screen) ? Vernacular.log("#{screen}: planned") : abort("vernacular: planning #{screen} failed")
    end

    def status_report
      require_setup!
      puts activity
      Queue.load.screens.each do |entry|
        line = format('%-20s %-8s', entry['screen'], entry['status'])
        line += " #{entry['progress']}" if entry['progress']
        line += " — #{entry['reason']}" if entry['reason']
        puts line
      end
      to_read = { 'vernacular/decisions.md' => Ledger.decisions.open_count, 'vernacular/improvements.md' => Ledger.improvements.open_count }
      to_read.each { |path, count| puts "#{count} to read in #{path}" if count.positive? }
    end

    private

    def run_screen(queue, screen)
      queue.update(screen, status: 'running')
      return finish(queue, screen, 'blocked', reason: 'planning failed') unless Plan.path(screen).exist? || plan_screen(queue, screen)

      done = Array(queue.find(screen)['done'])
      # Reloaded before every checkpoint, so one appended mid-run still runs.
      loop do
        plan = Plan.load(screen)
        checkpoint = plan.checkpoints.find { !done.include?(it.id) } or break

        queue.update(screen, progress: "#{done.size}/#{plan.checkpoints.size} → #{checkpoint.id}")
        resuming = @interrupted == screen && Gates.changed_files.any? { it != 'vernacular/queue.yml' }
        @interrupted = nil
        result = CheckpointRun.new(plan, checkpoint, resuming:).run
        if result == :blocked
          return finish(queue, screen, 'blocked', reason: "#{checkpoint.id}: see vernacular/evidence/#{screen}/#{checkpoint.id}/blocked.md")
        end

        done << checkpoint.id
        queue.update(screen, done:, progress: "#{done.size}/#{plan.checkpoints.size}")
        commit_bookkeeping("vernacular(#{screen}): progress #{done.size}/#{plan.checkpoints.size}")
        return pause!(queue, screen, checkpoint.id) if PAUSE.exist?
      end
      finish(queue, screen, 'done')
    end

    # A paused screen is not `running`, so the next run demands a clean tree
    # instead of treating the human's edits as an interrupted checkpoint.
    def pause!(queue, screen, after)
      PAUSE.delete
      queue.update(screen, status: 'paused')
      commit_bookkeeping("vernacular(#{screen}): paused")
      Vernacular.log("paused after #{screen}/#{after}; resume with vernacular run")
      'paused'
    end

    def claim_run!
      abort "vernacular: already running as pid #{running_pid}" if running_pid
      FileUtils.mkdir_p(TMP)
      File.write(PIDFILE, Process.pid.to_s)
      PAUSE.delete if PAUSE.exist?
      at_exit { PIDFILE.delete if PIDFILE.exist? && PIDFILE.read.to_i == Process.pid }
    end

    def running_pid
      pid = PIDFILE.exist? ? PIDFILE.read.to_i : 0
      return nil unless pid.positive?

      Process.kill(0, pid)
      pid
    rescue Errno::ESRCH
      nil
    rescue Errno::EPERM
      pid
    end

    def activity
      last = LOG.exist? ? LOG.readlines.last.to_s.strip : ''
      age = LOG.exist? ? ago(Time.now - LOG.mtime) : '-'
      if (pid = running_pid)
        findings = Dir[TMP.join('runs/**/round-*.txt').to_s].max_by { File.mtime(it) }
        [ "running · pid #{pid} · last log #{age} ago: #{last}",
          ('pause requested; stops after the current checkpoint' if PAUSE.exist?),
          ("latest findings: #{Pathname(findings).relative_path_from(ROOT)}" if findings) ].compact.join("\n")
      elsif (stuck = Queue.load.screens.find { it['status'] == 'running' })
        "stopped mid-screen (#{stuck['screen']}, no live process) · resume with vernacular run"
      else
        'idle'
      end
    end

    def ago(seconds)
      if seconds < 120 then "#{seconds.round}s"
      elsif seconds < 7200 then "#{(seconds / 60).round}m"
      else "#{(seconds / 3600).round}h"
      end
    end

    def finish(queue, screen, status, reason: nil)
      queue.update(screen, status:, reason:)
      commit_bookkeeping("vernacular(#{screen}): #{status}#{" — #{reason}" if reason}")
      status
    end

    def plan_screen(queue, screen)
      entry = queue.find(screen)
      session = SecureRandom.uuid
      message = Prompts.plan(entry)
      writable = [ "vernacular/screens/#{screen}/**", Vernacular.config.scenarios(screen) ].compact
      PLAN_ATTEMPTS.times do |attempt|
        Vernacular.log("#{screen}: planning (attempt #{attempt + 1})")
        reply = Claude.plan(message, session_id: session, resume: attempt.positive?, writable:)
        problems = plan_problems(screen, reply)
        if problems.empty?
          trailer = Vernacular.config.commit_trailer
          Shell.run('git', 'add', '--all')
          Shell.run('git', 'commit', '--no-verify', '-F', '-',
                    stdin: "vernacular(#{screen}): plan\n\n#{plan_summary(screen)}\n#{"\n#{trailer}\n" unless trailer.empty?}")
          return true
        end
        Vernacular.log("#{screen}: plan rejected: #{problems.first(3).join('; ')}")
        message = "The driver rejected the plan:\n#{problems.map { "- #{it}" }.join("\n")}\nFix the plan (and scenarios), then stop."
      end
      false
    end

    def plan_problems(screen, reply)
      return [ "planner errored: #{reply.raw}" ] unless reply.ok
      return [ "#{Plan.path(screen).relative_path_from(ROOT)} was not written" ] unless Plan.path(screen).exist?

      plan = Plan.load(screen)
      problems = plan.problems
      return problems if problems.any?

      scenarios = plan.checkpoints.flat_map(&:scenarios).uniq
      return [] if scenarios.empty?
      return [ 'the plan has UI checkpoints but config.yml has no capture commands; mark them ui: false' ] unless Vernacular.config.captures?

      capture = Capture.reference(scenarios)
      return [ "vernacular capture #{scenarios.join(',')} failed:\n#{capture.tail(60)}" ] unless capture.success?

      missing = plan.checkpoints.flat_map(&:states).uniq.reject { Capture.reference_png(*it.split(':', 2)).exist? }
      missing.map { "state #{it} is listed in plan.yml but the reference capture didn't produce it" }
    end

    def plan_summary(screen)
      Plan.load(screen).checkpoints.map { "- #{it.id} #{it.title}#{' (logic only)' unless it.ui}" }.join("\n")
    end

    def commit_bookkeeping(subject)
      paths = %w[vernacular/queue.yml vernacular/memory.md vernacular/evidence].select { ROOT.join(it).exist? }
      Shell.run('git', 'add', *paths)
      Shell.run('git', 'commit', '--no-verify', '-m', subject)
    end

    def require_setup!
      abort 'vernacular: no vernacular/config.yml here; run `vernacular init` first' unless Config::PATH.exist?
      abort 'vernacular: no vernacular/queue.yml' unless Queue::PATH.exist?
    end

    def require_clean_tree!
      dirty = Gates.changed_files
      abort "vernacular: commit or stash these first — vernacular commits the whole tree:\n#{dirty.join("\n")}" if dirty.any?
    end

    # A regression failure on a clean HEAD (a missing credentials key, a stale
    # test database) is not the implementer's to fix, yet the final gate
    # would feed it back every round until the checkpoint blocked.
    def require_green_baseline!
      Vernacular.log('checking the regression gate on HEAD')
      baseline = Gates.final
      return if baseline.passed

      abort "vernacular: the regression gate fails on HEAD before any change, so no checkpoint could pass it. " \
            "Fix the environment first.\n#{baseline.feedback}"
    end
  end
end
