module Vernacular
  # Runs a command, keeps all output, and never raises on failure: a gate
  # reads the result and decides.
  module Shell
    Result = Data.define(:command, :status, :output) do
      def success? = status.zero?

      def tail(lines = 120)
        output.lines.last(lines).join
      end
    end

    def self.run(*command, chdir: ROOT, env: {}, timeout: 1800, stdin: nil)
      output = +''
      status = nil
      Open3.popen2e(env, *command, chdir: chdir.to_s, pgroup: true) do |input, out, wait|
        input.write(stdin) if stdin
        input.close
        reader = Thread.new do
          out.each_line { output << it }
        rescue IOError
          nil
        end
        unless wait.join(timeout)
          Process.kill('-TERM', wait.pid)
          output << "\n[vernacular] timed out after #{timeout}s\n"
        end
        reader.join
        status = wait.value.exitstatus || 1
      end
      Result.new(command.join(' '), status, output)
    end

    # A command line from config.yml.
    def self.sh(line, env: {}, timeout: Vernacular.config.command_timeout)
      run('sh', '-c', line, env:, timeout:).with(command: line)
    end
  end
end
