# frozen_string_literal: true

require_relative "railslift/version"
require_relative "railslift/project_detector"
require_relative "railslift/upgrade_repository"
require_relative "railslift/upgrade_planner"
require_relative "railslift/outdated_checker"
require_relative "railslift/upgrade_checker"
require_relative "railslift/upgrade_guide"
require_relative "railslift/cli"

module Railslift
  class Error < StandardError; end
  # Your code goes here...
end
