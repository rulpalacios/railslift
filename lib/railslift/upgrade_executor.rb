# frozen_string_literal: true

require "rubygems"
require_relative "command_runner"
require_relative "project_detector"
require_relative "upgrade_checker"
require_relative "upgrade_guide"
require_relative "upgrade_planner"

module Railslift
  class UpgradeExecutor
    class Error < StandardError; end
    class UnsupportedTarget < Error; end
    class IncompatibleRuby < Error; end
    class MissingGemfile < Error; end
    class UnsupportedGemfile < Error; end
    class DirtyWorktree < Error; end
    class RuntimeUnavailable < Error; end
    class CommandFailed < Error; end

    RAILS_DECLARATION = /^(\s*gem\s+["']rails["']\s*,\s*)["'][^"']+["'](.*)$/

    def initialize(
      root_path:,
      target_version:,
      apply: false,
      runner: CommandRunner.new,
      runtime_version: RUBY_VERSION
    )
      @root_path = root_path
      @target_version = target_version
      @apply = apply
      @runner = runner
      @runtime_version = runtime_version
    end

    def call
      project = ProjectDetector.new(@root_path).call
      rails_version = project[:rails_version]
      raise Error, "Rails was not detected in #{@root_path}" unless rails_version

      plan = UpgradePlanner.new(
        current_version: rails_version,
        target_version: @target_version
      ).call
      step = validate_single_step!(plan)
      checks = UpgradeChecker.new(
        current_version: rails_version,
        target_version: @target_version,
        ruby_version: project[:ruby_version]
      ).call
      raise IncompatibleRuby, ruby_error(checks) unless checks[:compatible]

      guide = UpgradeGuide.new(from_version: step[:from], to_version: step[:to]).call
      gemfile_path = File.join(@root_path, "Gemfile")
      raise MissingGemfile, "Gemfile was not found in #{@root_path}" unless File.exist?(gemfile_path)

      original_gemfile = File.read(gemfile_path)
      updated_gemfile = update_rails_declaration(original_gemfile, step[:to])
      result = build_result(project, step, guide, original_gemfile, updated_gemfile)
      return result unless @apply

      ensure_clean_worktree!
      bundle_command = bundle_command_for(project[:ruby_version])
      apply_upgrade!(gemfile_path, original_gemfile, updated_gemfile, bundle_command)
      result.merge(applied: true)
    end

    private

    def validate_single_step!(plan)
      target_minor = minor(@target_version)
      step = plan[:steps].first

      if plan[:steps].length != 1 || step.nil? || step[:to] != target_minor
        raise UnsupportedTarget,
              "Upgrade must target the next Rails minor version only"
      end

      step
    end

    def update_rails_declaration(content, target)
      replacement = false
      updated = content.each_line.map do |line|
        match = line.match(RAILS_DECLARATION)
        next line unless match

        replacement = true
        "#{match[1]}\"~> #{target}.0\"#{match[2]}\n"
      end.join

      return updated if replacement

      raise UnsupportedGemfile,
            "Could not safely update the Rails declaration in Gemfile"
    end

    def ensure_clean_worktree!
      repository = @runner.capture("git", "rev-parse", "--is-inside-work-tree", chdir: @root_path)
      raise DirtyWorktree, "Upgrade application requires a Git repository" unless repository.success

      status = @runner.capture("git", "status", "--porcelain", chdir: @root_path)
      unless status.success && status.output.strip.empty?
        raise DirtyWorktree, "Git worktree must be clean before applying an upgrade"
      end
    end

    def bundle_command_for(project_ruby_version)
      version = normalized_ruby_version(project_ruby_version)
      return %w[bundle update rails] if Gem::Version.new(@runtime_version) == Gem::Version.new(version)

      mise = @runner.capture("mise", "--version", chdir: @root_path)
      unless mise.success
        raise RuntimeUnavailable,
              runtime_error(version, "mise is not available")
      end

      command = ["mise", "exec", "ruby@#{version}", "--", "bundle", "update", "rails"]
      runtime = @runner.capture(
        "mise", "exec", "ruby@#{version}", "--", "ruby", "-e", "print RUBY_VERSION",
        chdir: @root_path
      )
      unless runtime.success && runtime.output.strip == version
        raise RuntimeUnavailable,
              runtime_error(version, runtime.output.strip)
      end

      command
    end

    def apply_upgrade!(gemfile_path, original_gemfile, updated_gemfile, bundle_command)
      lockfile_path = File.join(@root_path, "Gemfile.lock")
      original_lockfile = File.exist?(lockfile_path) ? File.binread(lockfile_path) : nil

      File.write(gemfile_path, updated_gemfile)
      command = @runner.capture(*bundle_command, chdir: @root_path)
      return if command.success

      File.write(gemfile_path, original_gemfile)
      restore_lockfile(lockfile_path, original_lockfile)
      raise CommandFailed, "bundle update rails failed; project files were restored\n#{command.output}"
    end

    def restore_lockfile(path, content)
      if content
        File.binwrite(path, content)
      elsif File.exist?(path)
        File.delete(path)
      end
    end

    def build_result(project, step, guide, original_gemfile, updated_gemfile)
      {
        applied: false,
        current_version: project[:rails_version],
        target_version: step[:to],
        ruby_version: project[:ruby_version],
        gemfile_change: {
          before: rails_line(original_gemfile),
          after: rails_line(updated_gemfile)
        },
        command: "bundle update rails",
        next_steps: guide[:commands].reject { |command| command == "bundle update rails" },
        review: guide[:review]
      }
    end

    def rails_line(content)
      content.each_line.find { |line| line.match?(RAILS_DECLARATION) }&.strip
    end

    def ruby_error(checks)
      failed = checks[:steps].find { |step| !step[:ruby_compatible] }
      "Ruby #{checks[:ruby_version]} is incompatible; Rails #{failed[:to]} requires Ruby >= #{failed[:ruby_min]}"
    end

    def runtime_error(version, detail)
      message = <<~TEXT.strip
        The project requires Ruby #{version}, but Railslift is running with Ruby #{@runtime_version}.
        Install the project runtime with:
          mise install ruby@#{version}
        Then retry the same Railslift command.
      TEXT
      detail.empty? ? message : "#{message}\n#{detail}"
    end

    def normalized_ruby_version(version)
      version.to_s[/\d+(?:\.\d+)+/] || version
    end

    def minor(version)
      parsed = Gem::Version.new(version)
      "#{parsed.segments[0]}.#{parsed.segments[1]}"
    end
  end
end
