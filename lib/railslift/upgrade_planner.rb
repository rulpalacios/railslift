# frozen_string_literal: true

require "rubygems"
require_relative "upgrade_repository"

module Railslift
  class UpgradePlanner
    def initialize(current_version:, target_version:, repository: UpgradeRepository.new)
      @current_version = Gem::Version.new(current_version)
      @target_version = Gem::Version.new(target_version)
      @repository = repository
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
        next_version = @repository.next_version(current_minor)

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
