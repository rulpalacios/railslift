# frozen_string_literal: true

require_relative "railslift/version"
require_relative "railslift/cli"
require_relative "railslift/project_detector"
require_relative "railslift/upgrade_planner"

module Railslift
  class Error < StandardError; end
  # Your code goes here...
end
