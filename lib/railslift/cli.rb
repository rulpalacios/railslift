# frozen_string_literal: true

require "thor"
require_relative "project_detector"

module Railslift
  class CLI < Thor
    desc "doctor", "Detect Rails project information"

    def doctor
      result = ProjectDetector.new(Dir.pwd).call

      puts "Railslift Doctor"
      puts
      puts "Ruby: #{result[:ruby_version] || "Not detected"}"
      puts "Rails: #{result[:rails_version] || "Not detected"}"
      puts "Bundler: #{result[:bundler_version] || "Not detected"}"
      puts "Gemfile: #{result[:has_gemfile] ? "Found" : "Missing"}"
      puts "Gemfile.lock: #{result[:has_lockfile] ? "Found" : "Missing"}"
    end

    desc "plan", "Generate Rails upgrade plan"
    option :target, required: true

    def plan
      detector = ProjectDetector.new(Dir.pwd).call
      planner = UpgradePlanner.new(
        current_version: detector[:rails_version],
        target_version: options[:target]
      )

      result = planner.call

      puts "Railslift Plan"
      puts
      puts "Current Rails: #{result[:current_version]}"
      puts "Target Rails: #{result[:target_version]}"
      puts
      puts "Suggested path:"
      result[:steps].each { |step| puts "- #{step[:from]} → #{step[:to]}" }
    end
  end
end