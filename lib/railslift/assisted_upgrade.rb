# frozen_string_literal: true

require "tempfile"
require "rubygems"
require_relative "ai/fixer"
require_relative "command_runner"
require_relative "project_detector"

module Railslift
  class AssistedUpgrade
    class Error < StandardError; end
    class WrongTarget < Error; end
    class DirtyWorktree < Error; end
    class CommandFailed < Error; end
    class InvalidPatch < Error; end

    MAX_CONTEXT_BYTES = 40_000

    def initialize(root_path:, target_version:, fixer: AI::Fixer.new, runner: CommandRunner.new, approve:)
      @root_path = root_path
      @target_version = minor(target_version)
      @fixer = fixer
      @runner = runner
      @approve = approve
    end

    def call
      project = ProjectDetector.new(@root_path).call
      current = minor(project[:rails_version])
      raise WrongTarget, "AI assistance requires the project to already be on Rails #{@target_version}" unless current == @target_version

      ensure_clean_worktree!
      runtime = runtime_prefix(project[:ruby_version])

      return { status: :cancelled } unless @approve.call("Run bin/rails app:update now?")

      app_update = @runner.run(*runtime, "bin/rails", "app:update", chdir: @root_path)
      raise CommandFailed, "bin/rails app:update failed" unless app_update.success

      tests = @runner.capture(*runtime, "bin/rails", "test", chdir: @root_path)
      return { status: :tests_passed, test_output: tests.output } if tests.success

      context = build_context(tests.output)
      proposal = @fixer.call(context: context)
      return { status: :no_patch, summary: proposal[:summary], test_output: tests.output } if proposal[:patch].strip.empty?

      result = {
        status: :patch_proposed,
        summary: proposal[:summary],
        patch: proposal[:patch],
        test_output: tests.output
      }
      return result unless @approve.call("Apply this AI-generated patch?")

      apply_patch!(proposal[:patch])
      final_tests = @runner.capture(*runtime, "bin/rails", "test", chdir: @root_path)
      result.merge(
        status: final_tests.success ? :fixed : :tests_failed,
        final_test_output: final_tests.output
      )
    end

    private

    def ensure_clean_worktree!
      repository = @runner.capture("git", "rev-parse", "--is-inside-work-tree", chdir: @root_path)
      status = @runner.capture("git", "status", "--porcelain", chdir: @root_path)
      unless repository.success && status.success && status.output.strip.empty?
        raise DirtyWorktree,
              "Commit or stash current changes before running the AI-assisted upgrade"
      end
    end

    def runtime_prefix(version)
      normalized = version.to_s[/\d+(?:\.\d+)+/] || version
      return [] if Gem::Version.new(RUBY_VERSION) == Gem::Version.new(normalized)

      ["mise", "exec", "ruby@#{normalized}", "--"]
    end

    def build_context(test_output)
      diff = @runner.capture("git", "diff", "--", ".", chdir: @root_path).output
      {
        target_rails: @target_version,
        test_output: truncate(test_output),
        current_diff: truncate(diff),
        files: relevant_files(test_output)
      }
    end

    def relevant_files(output)
      paths = output.scan(%r{(?:\./)?(?:app|config|lib|test)/[\w./-]+\.rb}).uniq.first(12)
      paths.to_h do |relative|
        relative = relative.delete_prefix("./")
        path = File.expand_path(relative, @root_path)
        next [relative, ""] unless path.start_with?("#{@root_path}/") && File.file?(path)

        [relative, truncate(File.read(path))]
      end
    end

    def truncate(value)
      value.to_s.byteslice(0, MAX_CONTEXT_BYTES)
    end

    def apply_patch!(patch)
      Tempfile.create(["railslift", ".patch"]) do |file|
        file.write(patch)
        file.flush

        check = @runner.capture("git", "apply", "--check", file.path, chdir: @root_path)
        raise InvalidPatch, "AI patch could not be applied safely\n#{check.output}" unless check.success

        apply = @runner.capture("git", "apply", file.path, chdir: @root_path)
        raise InvalidPatch, "AI patch failed to apply\n#{apply.output}" unless apply.success
      end
    end

    def minor(version)
      parsed = Gem::Version.new(version)
      "#{parsed.segments[0]}.#{parsed.segments[1]}"
    end
  end
end
