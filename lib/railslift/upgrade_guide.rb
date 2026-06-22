# frozen_string_literal: true

require "rubygems"
require_relative "upgrade_repository"

module Railslift
  class UpgradeGuide
    class UnsupportedTransition < StandardError; end

    def initialize(from_version:, to_version:, repository: UpgradeRepository.new)
      @from_version = minor(from_version)
      @to_version = minor(to_version)
      @repository = repository
    end

    def call
      validate_transition!

      {
        from: @from_version,
        to: @to_version,
        ruby_min: @repository.ruby_min(@from_version),
        commands: @repository.commands(@from_version),
        review: @repository.checks(@from_version),
        documentation: @repository.documentation(@from_version)
      }
    end

    private

    def validate_transition!
      return if @repository.next_version(@from_version) == @to_version

      raise UnsupportedTransition,
            "Unsupported Rails upgrade transition: #{@from_version} → #{@to_version}"
    rescue KeyError
      raise UnsupportedTransition,
            "Unsupported Rails upgrade transition: #{@from_version} → #{@to_version}"
    end

    def minor(version)
      parsed = Gem::Version.new(version)
      "#{parsed.segments[0]}.#{parsed.segments[1]}"
    end
  end
end
