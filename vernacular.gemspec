Gem::Specification.new do |s|
  s.name = 'vernacular'
  s.version = '0.1.0'
  s.summary = 'Rebuild an app in a new stack, one machine-gated checkpoint at a time.'
  s.description = 'An autonomous Claude Code loop: plan a screen into checkpoints, implement each, and commit only ' \
                  'after build, test, visual, adversarial-review, and regression gates all pass.'
  s.authors = [ 'Mark Kraemer' ]
  s.license = 'MIT'
  s.homepage = 'https://github.com/mark-kraemer/vernacular'
  s.required_ruby_version = '>= 3.4'
  s.files = Dir['lib/**/*.rb', 'exe/*', 'prompts/*.md', 'templates/*', 'README.md', 'LICENSE']
  s.bindir = 'exe'
  s.executables = [ 'vernacular' ]
end
