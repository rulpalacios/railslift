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
  end
end