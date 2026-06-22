# frozen_string_literal: true

require "yaml"

module Railslift
  class GemCompatibilityRepository
    DATA_PATH = File.expand_path("data/gem_compatibility.yml", __dir__)

    def initialize(path: DATA_PATH)
      @data = YAML.load_file(path)
    end

    def rule(gem_name, target_version)
      @data.fetch("gems", {})
           .fetch(gem_name, {})
           .fetch("rails", {})
           .fetch(target_version, nil)
    end
  end
end
