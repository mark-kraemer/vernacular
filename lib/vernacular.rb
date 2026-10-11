require 'json'
require 'yaml'
require 'open3'
require 'pathname'
require 'fileutils'
require 'securerandom'
require 'shellwords'
require 'digest'
require 'time'

# Subprocess output (claude, build tools) is UTF-8 whatever the terminal's
# locale; under an unset LANG Ruby would read it as US-ASCII and crash.
Encoding.default_external = Encoding::UTF_8

# Vernacular: an autonomous, gated loop that rebuilds a reference app in a
# target stack, one checkpoint at a time. See README.md.
module Vernacular
  GEM = Pathname(__dir__).join('..').expand_path
  ROOT = Pathname(ENV.fetch('VERNACULAR_ROOT') { `git rev-parse --show-toplevel 2>/dev/null`.strip.then { it.empty? ? Dir.pwd : it } })
  HOME = ROOT.join('vernacular')
  TMP = ROOT.join('tmp/vernacular')
  LOG = TMP.join('vernacular.log')
  PIDFILE = TMP.join('run.pid')
  PAUSE = TMP.join('PAUSE')

  def self.config
    @config ||= Config.load
  end

  def self.log(message)
    line = "[#{Time.now.strftime('%H:%M:%S')}] #{message}"
    puts line
    FileUtils.mkdir_p(TMP)
    File.open(LOG, 'a') { it.puts(line) }
  end
end

require_relative 'vernacular/config'
require_relative 'vernacular/shell'
require_relative 'vernacular/claude'
require_relative 'vernacular/prompts'
require_relative 'vernacular/queue'
require_relative 'vernacular/plan'
require_relative 'vernacular/capture'
require_relative 'vernacular/gates'
require_relative 'vernacular/evidence'
require_relative 'vernacular/checks'
require_relative 'vernacular/ledger'
require_relative 'vernacular/improvement'
require_relative 'vernacular/checkpoint_run'
require_relative 'vernacular/driver'
