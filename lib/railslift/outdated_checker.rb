# frozen_string_literal: true

require "rubygems"
require_relative "upgrade_planner"
require_relative "upgrade_repository"

module Railslift
  class OutdatedChecker
    def initialize(current_version:, repository: UpgradeRepository.new)
      @current_version = Gem::Version.new(current_version)
      @repository = repository
    end

    def call
      latest_version = @repository.latest_rails_version
      plan = UpgradePlanner.new(
        current_version: @current_version,
        target_version: latest_version,
        repository: @repository
      ).call

      {
        current_version: @current_version.to_s,
        latest_version: latest_version,
        outdated: @current_version < Gem::Version.new(latest_version),
        steps: plan[:steps]
      }
    end
  end
end
