# frozen_string_literal: true

require "bundler"
require "rubygems"
require_relative "gem_compatibility_repository"

module Railslift
  class GemAnalyzer
    class MissingLockfile < StandardError; end
    class InvalidLockfile < StandardError; end

    FRAMEWORK_GEMS = %w[
      actioncable
      actionmailbox
      actionmailer
      actionpack
      actiontext
      actionview
      activejob
      activemodel
      activerecord
      activestorage
      activesupport
      rails
      railties
    ].freeze

    def initialize(root_path:, target_version:, repository: GemCompatibilityRepository.new)
      @root_path = root_path
      @target_version = minor(target_version)
      @repository = repository
    end

    def call
      parser = parse_lockfile
      dependencies = parser.dependencies.keys
                           .reject { |name| FRAMEWORK_GEMS.include?(name) }
                           .filter_map { |name| analyze_dependency(name, parser) }
                           .sort_by { |dependency| dependency[:name] }

      {
        target_version: @target_version,
        dependencies: dependencies,
        summary: dependencies.map { |dependency| dependency[:status] }.tally
      }
    end

    private

    def parse_lockfile
      path = File.join(@root_path, "Gemfile.lock")
      raise MissingLockfile, "Gemfile.lock was not found in #{@root_path}" unless File.exist?(path)

      Bundler::LockfileParser.new(Bundler.read_file(path))
    rescue Bundler::LockfileError => error
      raise InvalidLockfile, "Could not parse Gemfile.lock: #{error.message}"
    end

    def analyze_dependency(name, parser)
      spec = parser.specs.find { |candidate| candidate.name == name }
      return unless spec

      source = source_type(spec.source)
      base = {
        name: name,
        version: spec.version.to_s,
        source: source,
        framework_requirements: framework_requirements(spec)
      }

      return source_result(base, spec.source) unless source == :rubygems

      rule_result(base, @repository.rule(name, @target_version))
    end

    def source_result(base, source)
      base = base.reject { |key, _value| key == :framework_requirements }
      detail = if source_type(source) == :git
                 source.uri.to_s
               elsif source.respond_to?(:path)
                 source.path.to_s
               end

      base.merge(
        status: :warning,
        message: "#{base[:source].to_s.capitalize} dependency requires manual compatibility review",
        source_detail: detail
      )
    end

    def rule_result(base, rule)
      return declared_requirement_result(base) unless rule

      base = base.reject { |key, _value| key == :framework_requirements }
      requirement = rule["requirement"]
      compatible = requirement.nil? || Gem::Requirement.new(requirement).satisfied_by?(Gem::Version.new(base[:version]))
      status = compatible ? rule.fetch("status", "compatible").to_sym : :warning
      message = if compatible
                  rule.fetch("message", "Matches the known compatibility rule")
                else
                  "Version #{base[:version]} does not satisfy #{requirement}"
                end

      base.merge(status: status, message: message, requirement: requirement)
    end

    def declared_requirement_result(base)
      requirements = base.delete(:framework_requirements)
      return base.merge(status: :unknown, message: "No compatibility evidence for Rails #{@target_version}") if requirements.empty?

      target = Gem::Version.new(@target_version)
      incompatible = requirements.reject { |requirement| requirement[:requirement].satisfied_by?(target) }
      formatted = requirements.map { |requirement| "#{requirement[:name]} #{requirement[:requirement]}" }

      if incompatible.empty?
        base.merge(
          status: :compatible,
          message: "Declared framework requirements allow Rails #{@target_version}",
          requirements: formatted
        )
      else
        base.merge(
          status: :warning,
          message: "Declared framework requirements do not allow Rails #{@target_version}",
          requirements: formatted
        )
      end
    end

    def source_type(source)
      case source
      when Bundler::Source::Git then :git
      when Bundler::Source::Path then :path
      else :rubygems
      end
    end

    def minor(version)
      parsed = Gem::Version.new(version)
      "#{parsed.segments[0]}.#{parsed.segments[1]}"
    end

    def framework_requirements(spec)
      spec.dependencies.filter_map do |dependency|
        next unless FRAMEWORK_GEMS.include?(dependency.name)

        { name: dependency.name, requirement: dependency.requirement }
      end
    end
  end
end
