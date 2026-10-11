require 'tmpdir'
require_relative '../lib/vernacular'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
end
