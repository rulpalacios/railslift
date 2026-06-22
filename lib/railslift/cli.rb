# frozen_string_literal: true

require "json"
require "thor"
require_relative "ai/analyzer"
require_relative "assisted_upgrade"
require_relative "gem_analyzer"
require_relative "outdated_checker"
require_relative "project_detector"
require_relative "project_report"
require_relative "upgrade_checker"
require_relative "upgrade_executor"
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

    desc "report", "Generate a complete Rails upgrade report"
    option :target, required: true
    option :format, default: "text", enum: %w[text json]

    def report
      result = ProjectReport.new(
        root_path: Dir.pwd,
        target_version: options[:target]
      ).call

      if options[:format] == "json"
        puts JSON.pretty_generate(result)
        return
      end

      puts "Railslift Report"
      puts
      puts "Ruby: #{result[:project][:ruby_version]}"
      puts "Current Rails: #{result[:project][:rails_version]}"
      puts "Target Rails: #{result[:target_rails_version]}"
      puts "Bundler: #{result[:project][:bundler_version] || "Not detected"}"
      puts
      puts "Upgrade path:"
      result[:plan][:steps].each { |step| puts "- #{step[:from]} → #{step[:to]}" }
      puts
      puts "Compatibility:"
      puts "- Ruby: #{result[:summary][:ruby_compatible] ? "Compatible" : "Upgrade required"}"
      puts "- Gem warnings: #{result[:summary][:gem_warnings]}"
      puts "- Gems without compatibility evidence: #{result[:summary][:gems_unknown]}"
    rescue ProjectReport::MissingRails,
           ProjectReport::MissingRuby,
           GemAnalyzer::MissingLockfile,
           GemAnalyzer::InvalidLockfile => error
      raise Thor::Error, error.message
    end

    desc "analyze", "Analyze a Rails upgrade report with AI"
    option :target, required: true
    option :format, default: "text", enum: %w[text json]

    def analyze
      report = ProjectReport.new(
        root_path: Dir.pwd,
        target_version: options[:target]
      ).call
      result = AI::Analyzer.new.call(report: report)

      if options[:format] == "json"
        puts JSON.pretty_generate(result)
        return
      end

      puts "Railslift AI Analysis"
      puts
      puts "Risk level: #{result[:risk_level].capitalize}"
      puts
      puts result[:summary]

      unless result[:blockers].empty?
        puts
        puts "Blockers:"
        result[:blockers].each { |blocker| puts "- #{blocker}" }
      end

      unless result[:risks].empty?
        puts
        puts "Risks:"
        result[:risks].each do |risk|
          puts "- [#{risk[:severity].upcase}] #{risk[:title]}"
          puts "  Evidence: #{risk[:evidence]}"
          puts "  Recommendation: #{risk[:recommendation]}"
        end
      end

      puts
      puts "Recommended order:"
      result[:recommended_steps].sort_by { |step| step[:order] }.each do |step|
        puts "#{step[:order]}. #{step[:action]}"
        puts "   #{step[:rationale]}"
      end
    rescue ProjectReport::MissingRails,
           ProjectReport::MissingRuby,
           GemAnalyzer::MissingLockfile,
           GemAnalyzer::InvalidLockfile,
           AI::Provider::Error => error
      raise Thor::Error, error.message
    end

    desc "upgrade", "Prepare or apply the next Rails minor upgrade"
    option :target, required: true
    option :apply, type: :boolean, default: false
    option :ai, type: :boolean, default: false

    def upgrade
      if options[:ai]
        result = AssistedUpgrade.new(
          root_path: Dir.pwd,
          target_version: options[:target],
          approve: ->(question) { yes?("#{question} [y/N]") }
        ).call
        print_assisted_upgrade(result)
        return
      end

      result = UpgradeExecutor.new(
        root_path: Dir.pwd,
        target_version: options[:target],
        apply: options[:apply]
      ).call

      puts "Railslift Upgrade"
      puts
      puts "Rails #{result[:current_version]} → #{result[:target_version]}"
      puts "Ruby: #{result[:ruby_version]}"
      puts
      puts "Gemfile:"
      puts "- #{result[:gemfile_change][:before]}"
      puts "+ #{result[:gemfile_change][:after]}"
      puts
      puts "Command:"
      puts "- #{result[:command]}"

      if result[:applied]
        puts
        puts "Upgrade dependency update applied."
        puts
        puts "Next steps:"
        result[:next_steps].each { |step| puts "- #{step}" }
        return
      end

      puts
      puts "Preview only. No files were modified."
      puts "Run again with --apply to update Gemfile and Gemfile.lock."
    rescue UpgradeExecutor::Error,
           UpgradeGuide::UnsupportedTransition,
           AssistedUpgrade::Error,
           AI::Provider::Error => error
      raise Thor::Error, error.message
    end

    no_commands do
      def print_assisted_upgrade(result)
        puts "Railslift AI Upgrade"
        puts

        case result[:status]
        when :cancelled
          puts "Cancelled. No commands were run."
        when :tests_passed
          puts "Tests pass after app:update."
        when :no_patch
          puts result[:summary]
          puts "AI could not produce a safe patch."
        when :patch_proposed
          puts result[:summary]
          puts
          puts result[:patch]
          puts
          puts "Patch was not applied."
        when :fixed
          puts result[:summary]
          puts "AI patch applied and tests pass."
        when :tests_failed
          puts result[:summary]
          puts "AI patch applied, but tests still fail."
          puts result[:final_test_output]
        end
      end
    end
  end
end
