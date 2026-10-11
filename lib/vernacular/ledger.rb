module Vernacular
  # An append-only markdown checklist a human works through: entries start
  # `## [ ]` and are ticked `## [x]` once read. decisions.md records every
  # contract or plan change a checkpoint made on its own; improvements.md
  # holds harness changes the improver proposed but cannot make itself.
  class Ledger
    TITLES = {
      'decisions.md' => "# Vernacular decisions\n\nContract and plan changes checkpoints made without a human. Tick `[x]` once read; revert or amend anything you disagree with.\n",
      'improvements.md' => "# Vernacular improvements\n\nHarness changes the per-checkpoint improver proposed but may not make itself (prompts, gates, config). Tick `[x]` once handled.\n"
    }.freeze

    def self.decisions = new('decisions.md')
    def self.improvements = new('improvements.md')

    attr_reader :path

    def initialize(name, home: HOME)
      @name = name
      @path = home.join(name)
    end

    def append(heading, body)
      File.write(path, TITLES.fetch(@name)) unless path.exist?
      File.open(path, 'a') { it.puts("\n## [ ] #{heading}\n\n#{body.strip}\n") }
    end

    def open_count
      path.exist? ? path.read.scan(/^## \[ \]/).size : 0
    end
  end
end
