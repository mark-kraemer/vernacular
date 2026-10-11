module Vernacular
  # One data set, seeded once, and the screen states shown from it. Copy to
  # spec/vernacular/scenario.rb.
  #
  #   Vernacular::Scenario.define :login_filled do
  #     signed_out
  #     seed { { user: create(:user) } }
  #     state :new, path: -> { new_session_path }
  #   end
  #
  # `path`, `api`, and the state's block run inside the spec example, so route
  # helpers, Capybara, and `seeded` (the seed block's hash) are available.
  class Scenario
    NOW = Time.utc(2026, 1, 15, 17, 0, 0)

    State = Data.define(:name, :path, :api, :before)

    REGISTRY = {}

    attr_reader :name, :states, :seed_block

    def self.define(name, &)
      REGISTRY[name.to_s] = new(name.to_s).tap { it.instance_eval(&) }
    end

    def self.selected(names = ENV.fetch('VERNACULAR_SCENARIOS', ''))
      Dir[File.join(__dir__, 'scenarios', '*.rb')].each { require it }
      wanted = names.split(',').map(&:strip).reject(&:empty?)
      REGISTRY.values.select { wanted.empty? || wanted.include?(it.name) }
    end

    def initialize(name)
      @name = name
      @states = []
      @signed_in = true
    end

    def seed(&block) = @seed_block = block
    def signed_out = @signed_in = false
    def signed_in? = @signed_in

    def state(name, path:, api: -> { [] }, &before)
      @states << State.new(name.to_s, path, api, before)
    end
  end
end
