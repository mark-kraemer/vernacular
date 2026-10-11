require 'open3'

# Runs the real CLI in a throwaway git repo with a fake `claude` on PATH and
# shell one-liners as the project's build, test, and capture commands.
RSpec.describe 'the vernacular loop' do
  let(:repo) { Pathname(Dir.mktmpdir).realpath }
  let(:log) { repo.join('fake_claude.log') }
  let(:test_command) { 'grep -q round feature.txt && echo "PASS submitsForm"' }
  let(:max_rounds) { 8 }

  after { FileUtils.rm_rf(repo) }

  def write(path, body)
    repo.join(path).dirname.mkpath
    repo.join(path).write(body)
  end

  def git(*args) = Open3.capture2e('git', *args, chdir: repo.to_s).first

  def vernacular(*args, env: {})
    bin = repo.join('bin')
    bin.mkpath
    FileUtils.cp(File.expand_path('support/fake_claude', __dir__), bin.join('claude'))
    path = "#{bin}:#{ENV.fetch('PATH')}"
    Open3.capture2e({ 'PATH' => path, 'FAKE_CLAUDE_LOG' => log.to_s, 'VERNACULAR_ROOT' => nil }.merge(env),
                    File.expand_path('../exe/vernacular', __dir__), *args, chdir: repo.to_s).first
  end

  before do
    git('init', '-q')
    git('config', 'user.email', 'spec@example.com')
    git('config', 'user.name', 'Spec')
    write('.gitignore', "tmp/\nbin/\nfake_claude.log\n")
    write('CONTRACT.md', "# Rules\n")
    write('vernacular/config.yml', YAML.dump(
      'reference' => 'a web page', 'target' => 'a native screen', 'max_rounds' => max_rounds,
      'commands' => {
        'build' => [ 'true' ], 'test' => [ test_command ], 'test_passed' => 'PASS {name}', 'regression' => [ 'true' ],
        'capture_reference' => 'for s in $(echo $VERNACULAR_SCENARIOS | tr , " "); do mkdir -p $VERNACULAR_OUTPUT/$s; echo png > $VERNACULAR_OUTPUT/$s/new.png; done',
        'capture_target' => 'for st in $(echo $VERNACULAR_STATES | tr , " "); do s=${st%%:*}; mkdir -p $VERNACULAR_OUTPUT/$s; echo png > $VERNACULAR_OUTPUT/$s/${st#*:}.png; done'
      },
      'reviewers' => { 'architecture' => { 'docs' => [ 'CONTRACT.md' ], 'focus' => 'bugs' } }
    ))
    write('vernacular/prompts/architecture_reviewer.md', "Custom architecture review of {{checkpoint_id}}.\n")
    write('vernacular/queue.yml', YAML.dump([ { 'screen' => 'login', 'status' => 'pending', 'notes' => 'Signing in.' } ]))
    write('vernacular/memory.md', "# Vernacular memory\n")
    write('vernacular/screens/login/plan.yml', YAML.dump('checkpoints' => [
      { 'id' => '01-session-logic', 'title' => 'Session logic', 'goal' => 'Sign in.', 'ui' => false, 'tests' => [ 'submitsForm' ] },
      { 'id' => '02-form', 'title' => 'The form', 'goal' => 'Draw it.', 'scope' => 'The form.',
        'states' => [ 'login_empty:new' ], 'tests' => [ 'submitsForm' ] }
    ]))
    git('add', '--all')
    git('commit', '-q', '-m', 'setup')
  end

  it 'implements, gates, and commits every checkpoint with its evidence' do
    output = vernacular('run', env: { 'FAKE_TOUCH_CONTRACT' => '1' })

    expect(output).to include('login                done     2/2')
    subjects = git('log', '--format=%s').lines.map(&:strip)
    expect(subjects).to include('vernacular(login): [contract] 01-session-logic Session logic',
                                'vernacular(login): [contract] 02-form The form', 'vernacular(login): done')
    expect(git('log', '--format=%B', '--grep', '02-form')).to include('Passed every gate in round 1.', 'Evidence: vernacular/evidence/login/02-form/')
    gates = JSON.parse(repo.join('vernacular/evidence/login/02-form/gates.json').read).map { it['gate'] }
    expect(gates).to eq(%w[build behavior ui adversarial final])
    expect(repo.join('vernacular/evidence/login/02-form/ui_review.json')).to exist
    expect(repo.join('vernacular/decisions.md').read.scan('## [ ]').size).to eq(2)
    expect(repo.join('vernacular/memory.md').read).to include('Write the planned test before the code')
    expect(log.read).to include('Custom architecture review of 01-session-logic.')
    expect(git('status', '--porcelain')).to be_empty
  end

  context 'when a test only passes on the second attempt' do
    let(:test_command) { 'test $(wc -l < feature.txt) -ge 2 && echo "PASS submitsForm"' }

    it 'sends the failure back to the implementer and commits in round two' do
      vernacular('run')

      body = git('log', '--format=%B', '--grep', '01-session-logic')
      expect(body).to include('Passed every gate in round 2.')
      rounds = JSON.parse(repo.join('vernacular/evidence/login/01-session-logic/gates.json').read)
      expect(rounds.map { it.values_at('round', 'gate', 'passed') }).to include([ 1, 'behavior', false ], [ 2, 'behavior', true ])
      expect(repo.join('vernacular/improvements.md').read).to include('## [ ] Faster tests (login/01-session-logic)')
    end
  end

  context 'when the planned test never passes' do
    let(:test_command) { 'echo "FAIL submitsForm"' }
    let(:max_rounds) { 2 }

    it 'stashes the work, writes blocked.md, and marks the screen blocked' do
      output = vernacular('run')

      expect(output).to include('login                blocked', 'see vernacular/evidence/login/01-session-logic/blocked.md')
      expect(git('stash', 'list')).to include('vernacular blocked login/01-session-logic')
      expect(repo.join('vernacular/evidence/login/01-session-logic/blocked.md').read).to include('out of rounds (2)')
      expect(repo.join('feature.txt')).not_to exist
      expect(git('status', '--porcelain')).to be_empty
    end
  end

  it 'plans a screen, proves its states render in the reference, and commits the plan' do
    plan = YAML.dump('checkpoints' => [ { 'id' => '01-form', 'title' => 'The form', 'goal' => 'Draw it.', 'scope' => 'The form.',
                                          'states' => [ 'signup_empty:new' ], 'tests' => [ 'showsForm' ] } ])
    write('vernacular/queue.yml', YAML.dump([ { 'screen' => 'signup', 'status' => 'pending', 'notes' => 'Creating an account.' } ]))
    git('commit', '-qam', 'queue signup')

    vernacular('plan', 'signup', env: { 'FAKE_PLAN' => plan })

    expect(git('log', '-1', '--format=%B')).to start_with("vernacular(signup): plan\n\n- 01-form The form")
    expect(repo.join('tmp/vernacular/reference/signup_empty/new.png')).to exist
    expect(log.read).to include('Screen: **signup**', 'What it covers: Creating an account.')
  end

  it 'refuses to start on a dirty tree' do
    write('stray.txt', 'x')

    expect(vernacular('run')).to include('commit or stash these first', 'stray.txt')
  end
end
