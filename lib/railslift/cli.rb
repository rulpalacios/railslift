# frozen_string_literal: true

require "thor"
require_relative "outdated_checker"
require_relative "project_detector"
require_relative "upgrade_checker"
require_relative "upgrade_planner"

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

    desc "outdated", "Check whether Rails is outdated"

    def outdated
      detector = ProjectDetector.new(Dir.pwd).call
      rails_version = detector[:rails_version]

      raise Thor::Error, "Rails was not detected in #{Dir.pwd}" unless rails_version

      result = OutdatedChecker.new(current_version: rails_version).call

      puts "Railslift Outdated"
      puts
      puts "Current Rails: #{result[:current_version]}"
      puts "Latest Rails: #{result[:latest_version]}"
      puts

      unless result[:outdated]
        puts "Rails is up to date."
        return
      end

      puts "Upgrade path:"
      result[:steps].each { |step| puts "- #{step[:from]} → #{step[:to]}" }
    end

    desc "checks", "Check Rails upgrade requirements"
    option :target, required: true

    def checks
      detector = ProjectDetector.new(Dir.pwd).call
      rails_version = detector[:rails_version]
      ruby_version = detector[:ruby_version]

      raise Thor::Error, "Rails was not detected in #{Dir.pwd}" unless rails_version
      raise Thor::Error, "Ruby was not detected in #{Dir.pwd}" unless ruby_version

      result = UpgradeChecker.new(
        current_version: rails_version,
        target_version: options[:target],
        ruby_version: ruby_version
      ).call

      puts "Railslift Checks"
      puts
      puts "Current Rails: #{result[:current_version]}"
      puts "Target Rails: #{result[:target_version]}"
      puts "Current Ruby: #{result[:ruby_version]}"

      if result[:steps].empty?
        puts
        puts "No upgrade checks are required."
        return
      end

      result[:steps].each do |step|
        status = step[:ruby_compatible] ? "✓" : "✗"

        puts
        puts "Rails #{step[:from]} → #{step[:to]}"
        puts "#{status} Ruby #{result[:ruby_version]} (required: >= #{step[:ruby_min]})"
        puts "Checks:"
        step[:checks].each { |check| puts "- #{check}" }
      end
    end
  end
end
