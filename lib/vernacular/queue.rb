module Vernacular
  # vernacular/queue.yml: the screens in migration order and where each stands.
  class Queue
    PATH = HOME.join('queue.yml')

    def self.load
      new(YAML.load_file(PATH) || [])
    end

    attr_reader :screens

    def initialize(screens)
      @screens = screens
    end

    def find(name)
      screens.find { it['screen'] == name } or abort "vernacular: no screen #{name} in #{PATH}"
    end

    def pending
      screens.reject { %w[done blocked].include?(it['status']) }
    end

    def update(name, **changes)
      find(name).merge!(changes.transform_keys(&:to_s))
      File.write(PATH, YAML.dump(screens))
    end
  end
end
