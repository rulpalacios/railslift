# frozen_string_literal: true

require "rubygems"
require_relative "upgrade_planner"
require_relative "upgrade_repository"

module Railslift
  class UpgradeChecker
    def initialize(current_version:, target_version:, ruby_version:, repository: UpgradeRepository.new)
      @current_version = current_version
      @target_version = target_version
      @ruby_version = Gem::Version.new(normalize_version(ruby_version))
      @repository = repository
    end

    def call
      plan = UpgradePlanner.new(
        current_version: @current_version,
        target_version: @target_version,
        repository: @repository
      ).call
      steps = plan[:steps].map { |step| build_check(step) }

      {
        current_version: plan[:current_version],
        target_version: plan[:target_version],
        ruby_version: @ruby_version.to_s,
        compatible: steps.all? { |step| step[:ruby_compatible] },
        steps: steps
      }
    end

    private

    def build_check(step)
      ruby_min = @repository.ruby_min(step[:from])

      step.merge(
        ruby_min: ruby_min,
        ruby_compatible: @ruby_version >= Gem::Version.new(ruby_min),
        checks: @repository.checks(step[:from])
      )
    end

    def normalize_version(version)
      version.to_s[/\d+(?:\.\d+)+/] || version
    end
  end
end
