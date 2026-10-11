RSpec.describe Vernacular do
  def check(**overrides)
    Vernacular::Checks::Check.new(name: 'no-async-image', why: 'rule 30', paths: [ 'tmp/spec/**/*.swift' ],
                                  pattern: 'AsyncImage\(', message: 'Draw photos through CachedPhoto.', **overrides)
  end

  describe Vernacular::Checks do
    let(:dir) { Vernacular::ROOT.join('tmp/spec/Views') }

    before { FileUtils.mkdir_p(dir) }
    after { FileUtils.rm_rf(Vernacular::ROOT.join('tmp/spec')) }

    it 'reports each violating line of a changed file the check covers' do
      dir.join('Card.swift').write("VStack {\n  AsyncImage(url: url)\n}\n")
      dir.join('Card.md').write("AsyncImage(url: url)\n")

      found = described_class.violations([ check ], [ 'tmp/spec/Views/Card.swift', 'tmp/spec/Views/Card.md' ])

      expect(found.map { [ it.file, it.line ] }).to eq([ [ 'tmp/spec/Views/Card.swift', 2 ] ])
      expect(described_class.report(found)).to include('no-async-image: Draw photos through CachedPhoto', 'Card.swift:2')
    end

    it 'accepts a check that nothing in the tree violates' do
      expect(described_class.problem(check, [])).to be_nil
    end

    it 'rejects a check that matches code already in the tree' do
      problem = described_class.problem(check(paths: [ 'lib/**/*.rb' ], pattern: 'module Vernacular'), [])

      expect(problem).to start_with('matches code already in the tree: lib/')
    end

    it 'rejects a pattern that does not compile, a taken name, and a non-kebab name' do
      expect(described_class.problem(check(pattern: 'AsyncImage('), [])).to start_with('pattern does not compile')
      expect(described_class.problem(check, [ 'no-async-image' ])).to eq('no-async-image already exists')
      expect(described_class.problem(check(name: 'No AsyncImage'), [])).to eq('name must be kebab-case')
    end
  end

  describe Vernacular::Ledger do
    it 'counts entries until they are ticked' do
      Dir.mktmpdir do |home|
        ledger = described_class.new('decisions.md', home: Pathname(home))
        ledger.append('login/01 (2026-10-10)', "```diff\n-old\n+new\n```")
        ledger.append('login/02 (2026-10-10)', 'second')

        expect(ledger.open_count).to eq(2)

        ledger.path.write(ledger.path.read.sub('## [ ]', '## [x]'))
        expect(ledger.open_count).to eq(1)
        expect(ledger.path.read).to start_with('# Vernacular decisions')
      end
    end
  end

  describe Vernacular::Plan do
    def plan(**checkpoint)
      described_class.new('login', 'checkpoints' => [ { 'id' => '01-form', 'goal' => 'Build it.', 'scope' => 'The form.',
                                                         'states' => [ 'login_empty:new' ], 'tests' => [ 'showsForm' ] }.merge(checkpoint) ])
    end

    it 'accepts a well-formed plan' do
      expect(plan.problems).to be_empty
    end

    it 'rejects malformed checkpoints' do
      expect(plan('id' => 'form').problems).to include('form: id must look like 01-short-slug')
      expect(plan('tests' => []).problems).to include('01-form: no tests')
      expect(plan('states' => []).problems).to include('01-form: ui checkpoint needs scope and states')
      expect(plan('states' => [ 'login' ]).problems).to include('01-form: state "login" must be scenario:state')
      expect(plan('ui' => false, 'states' => [], 'scope' => nil).problems).to be_empty
    end
  end

  describe Vernacular::Config do
    it 'falls back to defaults and records every reviewer doc as contract' do
      config = described_class.new('reviewers' => { 'arch' => { 'docs' => [ 'RULES.md' ] }, 'ui' => { 'docs' => [ 'DESIGN.md', 'RULES.md' ] } })

      expect(config.max_rounds).to eq(8)
      expect(config.visible).to eq([ '.' ])
      expect(config.contract).to eq([ 'RULES.md', 'DESIGN.md', 'vernacular/screens' ])
      expect(described_class.new({}).reviewers.keys).to eq(%w[architecture guidelines])
    end
  end
end
