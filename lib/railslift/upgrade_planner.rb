# frozen_string_literal: true

require "yaml"
require "rubygems"

module Railslift
  class UpgradePlanner
    DATA_PATH = File.expand_path("data/rails_upgrade_paths.yml", __dir__)

    def initialize(current_version:, target_version:)
      @current_version = Gem::Version.new(current_version)
      @target_version = Gem::Version.new(target_version)
      @paths = YAML.load_file(DATA_PATH)
    end

    def call
      {
        current_version: @current_version.to_s,
        target_version: @target_version.to_s,
        steps: build_steps
      }
    end

    private

    def build_steps
      steps = []
      current_minor = minor(@current_version)

      while Gem::Version.new(current_minor) < @target_version
        version_config = @paths.fetch("versions").fetch(current_minor)
        next_version = version_config.fetch("next")

        break if next_version.nil?

        steps << {
          from: current_minor,
          to: next_version
        }

        current_minor = next_version
      end

      steps
    end

    def minor(version)
      "#{version.segments[0]}.#{version.segments[1]}"
    end
  end
end