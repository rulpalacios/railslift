# frozen_string_literal: true

module Railslift
  class ProjectDetector
    def initialize(root_path)
      @root_path = root_path
    end

    def call
      {
        ruby_version: ruby_version,
        rails_version: rails_version,
        bundler_version: bundler_version,
        has_gemfile: File.exist?(File.join(@root_path, "Gemfile")),
        has_lockfile: File.exist?(File.join(@root_path, "Gemfile.lock"))
      }
    end

    private

    def ruby_version
      path = File.join(@root_path, ".ruby-version")
      return File.read(path).strip if File.exist?(path)

      RUBY_VERSION
    end

    def rails_version
      lockfile = File.join(@root_path, "Gemfile.lock")
      return unless File.exist?(lockfile)

      content = File.read(lockfile)
      content[/^\s{4}rails \((.+)\)$/, 1]
    end

    def bundler_version
      lockfile = File.join(@root_path, "Gemfile.lock")
      return unless File.exist?(lockfile)

      content = File.read(lockfile)
      content[/BUNDLED WITH\n\s+(.+)/, 1]
    end
  end
end