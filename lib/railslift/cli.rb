# frozen_string_literal: true

require "thor"
require_relative "gem_analyzer"
require_relative "outdated_checker"
require_relative "project_detector"
require_relative "upgrade_checker"
require_relative "upgrade_guide"
require_relative "upgrade_planner"

module Railslift
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

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

    desc "upgrade-guide FROM TO", "Show guidance for a Rails upgrade transition"

    def upgrade_guide(from, to)
      result = UpgradeGuide.new(from_version: from, to_version: to).call

      puts "Railslift Upgrade Guide"
      puts
      puts "Rails #{result[:from]} → #{result[:to]}"
      puts "Required Ruby: >= #{result[:ruby_min]}"
      puts
      puts "Commands:"
      result[:commands].each { |command| puts "- #{command}" }
      puts
      puts "Review:"
      result[:review].each { |item| puts "- #{item}" }
      puts
      puts "Documentation:"
      puts "- Upgrade guide: #{result[:documentation].fetch("upgrade_guide")}"
      puts "- Release notes: #{result[:documentation].fetch("release_notes")}"
    rescue UpgradeGuide::UnsupportedTransition => error
      raise Thor::Error, error.message
    end

    desc "gems", "Analyze direct gem dependencies for a Rails target"
    option :target, required: true

    def gems
      result = GemAnalyzer.new(root_path: Dir.pwd, target_version: options[:target]).call

      puts "Railslift Gem Analysis"
      puts
      puts "Target Rails: #{result[:target_version]}"
      puts

      if result[:dependencies].empty?
        puts "No direct dependencies found."
        return
      end

      result[:dependencies].each do |dependency|
        marker = { compatible: "✓", warning: "!", unknown: "?" }.fetch(dependency[:status])
        puts "#{marker} #{dependency[:name]} #{dependency[:version]} [#{dependency[:source]}]"
        puts "  #{dependency[:message]}"
        puts "  Source: #{dependency[:source_detail]}" if dependency[:source_detail]
      end

      puts
      puts "Summary:"
      puts "- Compatible: #{result[:summary].fetch(:compatible, 0)}"
      puts "- Warnings: #{result[:summary].fetch(:warning, 0)}"
      puts "- Unknown: #{result[:summary].fetch(:unknown, 0)}"
    rescue GemAnalyzer::MissingLockfile, GemAnalyzer::InvalidLockfile => error
      raise Thor::Error, error.message
    end
  end
end
