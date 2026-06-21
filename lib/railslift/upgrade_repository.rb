# frozen_string_literal: true

require "yaml"

module Railslift
  class UpgradeRepository
    DATA_PATH = File.expand_path("data/rails_upgrade_paths.yml", __dir__)

    def initialize(path: DATA_PATH)
      @data = YAML.load_file(path)
    end

    def latest_rails_version
      @data.fetch("latest").fetch("rails")
    end

    def next_version(version)
      version_data(version).fetch("next")
    end

    def ruby_min(version)
      version_data(version).fetch("ruby_min")
    end

    def checks(version)
      version_data(version).fetch("checks", [])
    end

    private

    def version_data(version)
      @data.fetch("versions").fetch(version)
    end
  end
end
