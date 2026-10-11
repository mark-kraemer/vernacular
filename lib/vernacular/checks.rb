module Vernacular
  # vernacular/checks/*.yml: deterministic line checks the improver writes
  # after a checkpoint, so a finding that is mechanically detectable is caught
  # by the build gate instead of costing a review round. Each is a regex over
  # the lines of changed files matching a glob. The build gate reads them from
  # HEAD, so the implementer cannot loosen one to get past it.
  module Checks
    DIR = 'vernacular/checks'.freeze
    NAME = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    Check = Data.define(:name, :why, :paths, :pattern, :message)
    Violation = Data.define(:check, :file, :line, :text)

    def self.committed
      listing = Shell.run('git', 'ls-tree', '--name-only', 'HEAD', "#{DIR}/")
      return [] unless listing.success?

      listing.output.lines.map(&:strip).select { it.end_with?('.yml') }.filter_map do |path|
        parse(YAML.safe_load(Shell.run('git', 'show', "HEAD:#{path}").output))
      end
    end

    def self.parse(data)
      return nil unless data.is_a?(Hash)

      Check.new(name: data['name'].to_s, why: data['why'].to_s, paths: Array(data['paths']).map(&:to_s),
                pattern: data['pattern'].to_s, message: data['message'].to_s)
    end

    def self.violations(checks, files)
      checks.flat_map do |check|
        regex = Regexp.new(check.pattern)
        files.select { |file| matches?(check, file) && ROOT.join(file).file? }.flat_map do |file|
          ROOT.join(file).each_line.with_index(1).filter_map do |text, line|
            Violation.new(check:, file:, line:, text: text.strip) if text.scrub.match?(regex)
          end
        end
      end
    end

    def self.matches?(check, file)
      check.paths.any? { File.fnmatch?(it, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
    end

    # A new check must parse, compile, name a fresh file, and pass on the
    # code already accepted, so it only ever forbids what has not shipped.
    def self.problem(check, existing_names)
      return 'name must be kebab-case' unless check.name.match?(NAME)
      return "#{check.name} already exists" if existing_names.include?(check.name)
      return 'why, paths, pattern, and message are all required' if [ check.why, check.pattern, check.message ].any?(&:empty?) || check.paths.empty?

      Regexp.new(check.pattern)
      files = Shell.run('git', 'ls-files', '--cached', '--others', '--exclude-standard').output.lines.map(&:strip)
      hits = violations([ check ], files)
      "matches code already in the tree: #{hits.first(3).map { "#{it.file}:#{it.line}" }.join(', ')}" if hits.any?
    rescue RegexpError => e
      "pattern does not compile: #{e.message}"
    end

    def self.write(check)
      path = ROOT.join(DIR, "#{check.name}.yml")
      FileUtils.mkdir_p(path.dirname)
      File.write(path, YAML.dump(check.to_h.transform_keys(&:to_s)))
    end

    def self.report(found)
      found.group_by(&:check).map do |check, hits|
        "#{check.name}: #{check.message}\n  (why: #{check.why})\n" + hits.first(20).map { "  #{it.file}:#{it.line}: #{it.text[0, 160]}" }.join("\n")
      end.join("\n")
    end
  end
end
