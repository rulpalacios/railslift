# frozen_string_literal: true

require_relative "gem_analyzer"
require_relative "project_detector"
require_relative "upgrade_checker"
require_relative "upgrade_planner"
require_relative "version"

module Railslift
  class ProjectReport
    class MissingRails < StandardError; end
    class MissingRuby < StandardError; end

    SCHEMA_VERSION = 1

    def initialize(root_path:, target_version:)
      @root_path = root_path
      @target_version = target_version
    end

    def call
      project = ProjectDetector.new(@root_path).call
      validate_project!(project)

      plan = UpgradePlanner.new(
        current_version: project[:rails_version],
        target_version: @target_version
      ).call
      checks = UpgradeChecker.new(
        current_version: project[:rails_version],
        target_version: @target_version,
        ruby_version: project[:ruby_version]
      ).call
      gems = GemAnalyzer.new(
        root_path: @root_path,
        target_version: @target_version
      ).call

      {
        schema_version: SCHEMA_VERSION,
        generated_by: {
          name: "railslift",
          version: Railslift::VERSION
        },
        project: project,
        target_rails_version: @target_version,
        plan: plan,
        checks: checks,
        gems: gems,
        summary: build_summary(checks, gems)
      }
    end

    private

    def validate_project!(project)
      raise MissingRails, "Rails was not detected in #{@root_path}" unless project[:rails_version]
      raise MissingRuby, "Ruby was not detected in #{@root_path}" unless project[:ruby_version]
    end

    def build_summary(checks, gems)
      {
        ruby_compatible: checks[:compatible],
        gem_warnings: gems[:summary].fetch(:warning, 0),
        gems_unknown: gems[:summary].fetch(:unknown, 0)
      }
    end
  end
end
