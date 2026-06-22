# frozen_string_literal: true

require_relative "railslift/version"
require_relative "railslift/ai/provider"
require_relative "railslift/ai/providers/openai"
require_relative "railslift/ai/provider_factory"
require_relative "railslift/ai/analyzer"
require_relative "railslift/ai/fixer"
require_relative "railslift/assisted_upgrade"
require_relative "railslift/gem_compatibility_repository"
require_relative "railslift/gem_analyzer"
require_relative "railslift/command_runner"
require_relative "railslift/project_detector"
require_relative "railslift/project_report"
require_relative "railslift/upgrade_repository"
require_relative "railslift/upgrade_planner"
require_relative "railslift/outdated_checker"
require_relative "railslift/upgrade_checker"
require_relative "railslift/upgrade_executor"
require_relative "railslift/upgrade_guide"
require_relative "railslift/cli"

module Railslift
  class Error < StandardError; end
  # Your code goes here...
end
