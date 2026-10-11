require 'rails_helper'
require_relative 'scenario'

# The reference half of the UI gate. Copy to spec/vernacular/capture_spec.rb.
# For each scenario: seed once with the clock frozen, then for each state
# screenshot the page as the native shell's web view sees it, and record the
# API responses the native screen needs so both sides draw identical data.
#
# Needs from the app: `sign_in_as(user)` and `fixture_headers(user)` (the
# Authorization header the native app would send).
FIXTURES = Rails.root.join(ENV.fetch('VERNACULAR_FIXTURES', 'ios/Kit/Sources/Kit/Resources/Fixtures'))
ROUTES = Rails.root.join('tmp/vernacular/routes')

Capybara.register_driver :vernacular_reference do |app|
  Capybara::Playwright::Driver.new(app, browser_type: :webkit, headless: true, viewport: { width: 393, height: 852 },
                                        deviceScaleFactor: 3, userAgent: ENV.fetch('VERNACULAR_USER_AGENT', 'Hotwire Native iOS'))
end

RSpec.describe 'Vernacular reference capture', type: :system do
  before { driven_by :vernacular_reference }

  Vernacular::Scenario.selected.each do |scenario|
    it scenario.name do
      travel_to Vernacular::Scenario::NOW
      seeded = scenario.seed_block ? instance_exec(&scenario.seed_block) : {}
      define_singleton_method(:seeded) { seeded }
      page.driver.with_playwright_page { it.clock.set_fixed_time(Vernacular::Scenario::NOW) }
      sign_in_as(seeded.fetch(:user)) if scenario.signed_in?

      client = ActionDispatch::Integration::Session.new(Rails.application).tap { it.host = 'www.example.com' }
      headers = { 'Accept' => 'application/json' }.merge(scenario.signed_in? ? fixture_headers(seeded.fetch(:user)) : {})
      routes = {}
      responses = {}
      scenario.states.each do |state|
        path = instance_exec(&state.path)
        visit path
        instance_exec(&state.before) if state.before
        page.execute_script('document.activeElement?.blur()')
        out = Pathname(ENV.fetch('VERNACULAR_OUTPUT')).join(scenario.name, "#{state.name}.png")
        FileUtils.mkdir_p(out.dirname)
        page.driver.with_playwright_page { it.screenshot(path: out.to_s, animations: 'disabled') }

        routes[state.name] = path
        instance_exec(&state.api).each do |request|
          verb, url = request.split(' ', 2)
          client.process(verb.downcase.to_sym, url, headers:)
          responses[request] = { status: client.response.status, body: client.response.parsed_body.presence }
        end
      end

      FileUtils.mkdir_p([ FIXTURES, ROUTES ])
      File.write(ROUTES.join("#{scenario.name}.json"), JSON.generate(routes))
      File.write(FIXTURES.join("#{scenario.name}.json"),
                 JSON.pretty_generate(now: Vernacular::Scenario::NOW.iso8601, states: routes, responses: responses.sort.to_h) + "\n")
    end
  end
end
