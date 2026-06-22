# frozen_string_literal: true

require "json"
require "test_helper"
require "tmpdir"
require "fileutils"

class TestRailslift < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Railslift::VERSION
  end

  def test_outdated_checker_builds_a_path_to_latest_rails
    result = Railslift::OutdatedChecker.new(current_version: "7.0.4.2").call

    assert_equal "7.0.4.2", result[:current_version]
    assert_equal "8.1.3", result[:latest_version]
    assert result[:outdated]
    assert_equal [
      { from: "7.0", to: "7.1" },
      { from: "7.1", to: "7.2" },
      { from: "7.2", to: "8.0" },
      { from: "8.0", to: "8.1" }
    ], result[:steps]
  end

  def test_outdated_checker_reports_latest_patch_as_up_to_date
    result = Railslift::OutdatedChecker.new(current_version: "8.1.3").call

    refute result[:outdated]
    assert_empty result[:steps]
  end

  def test_outdated_command_prints_the_upgrade_path
    detector = Object.new
    detector.define_singleton_method(:call) { { rails_version: "7.0.4.2" } }

    output, = capture_io do
      Railslift::ProjectDetector.stub(:new, ->(*) { detector }) do
        Railslift::CLI.start(["outdated"])
      end
    end

    assert_includes output, "Current Rails: 7.0.4.2"
    assert_includes output, "Latest Rails: 8.1.3"
    assert_includes output, "- 7.0 → 7.1"
    assert_includes output, "- 8.0 → 8.1"
  end

  def test_upgrade_checker_builds_checks_for_each_step
    result = Railslift::UpgradeChecker.new(
      current_version: "7.0.4.2",
      target_version: "7.2",
      ruby_version: "ruby-3.2.2"
    ).call

    assert result[:compatible]
    assert_equal "3.2.2", result[:ruby_version]
    assert_equal 2, result[:steps].length
    assert_equal "7.0", result[:steps].first[:from]
    assert_equal "7.1", result[:steps].first[:to]
    assert_equal "2.7.0", result[:steps].first[:ruby_min]
    refute_empty result[:steps].first[:checks]
  end

  def test_upgrade_checker_detects_incompatible_ruby
    result = Railslift::UpgradeChecker.new(
      current_version: "7.2.2",
      target_version: "8.0",
      ruby_version: "3.1.4"
    ).call

    refute result[:compatible]
    refute result[:steps].first[:ruby_compatible]
    assert_equal "3.2.0", result[:steps].first[:ruby_min]
  end

  def test_upgrade_checker_uses_rails_7_2_ruby_requirement
    result = Railslift::UpgradeChecker.new(
      current_version: "7.1.5",
      target_version: "7.2",
      ruby_version: "3.0.7"
    ).call

    refute result[:compatible]
    assert_equal "3.1.0", result[:steps].first[:ruby_min]
  end

  def test_checks_command_prints_requirements
    detector = Object.new
    detector.define_singleton_method(:call) do
      { rails_version: "7.0.4.2", ruby_version: "3.2.2" }
    end

    output, = capture_io do
      Railslift::ProjectDetector.stub(:new, ->(*) { detector }) do
        Railslift::CLI.start(["checks", "--target", "7.1"])
      end
    end

    assert_includes output, "Railslift Checks"
    assert_includes output, "Rails 7.0 → 7.1"
    assert_includes output, "✓ Ruby 3.2.2 (required: >= 2.7.0)"
    assert_includes output, "Run rails app:update"
  end

  def test_upgrade_guide_returns_transition_guidance
    result = Railslift::UpgradeGuide.new(
      from_version: "7.0.4.2",
      to_version: "7.1.5"
    ).call

    assert_equal "7.0", result[:from]
    assert_equal "7.1", result[:to]
    assert_equal "2.7.0", result[:ruby_min]
    assert_includes result[:commands], "bundle update rails"
    assert_includes result[:review], "Review deprecated configuration"
    assert_equal "https://guides.rubyonrails.org/7_1_release_notes.html",
                 result[:documentation]["release_notes"]
  end

  def test_upgrade_guide_rejects_non_consecutive_transition
    error = assert_raises(Railslift::UpgradeGuide::UnsupportedTransition) do
      Railslift::UpgradeGuide.new(from_version: "7.0", to_version: "7.2").call
    end

    assert_includes error.message, "7.0 → 7.2"
  end

  def test_upgrade_guide_command_prints_guidance
    output, = capture_io do
      Railslift::CLI.start(["upgrade-guide", "7.0", "7.1"])
    end

    assert_includes output, "Railslift Upgrade Guide"
    assert_includes output, "Rails 7.0 → 7.1"
    assert_includes output, "Required Ruby: >= 2.7.0"
    assert_includes output, "bundle update rails"
    assert_includes output, "https://guides.rubyonrails.org/7_1_release_notes.html"
  end

  def test_gem_analyzer_classifies_registry_git_and_path_dependencies
    Dir.mktmpdir do |root|
      File.write(File.join(root, "Gemfile.lock"), sample_lockfile)

      result = Railslift::GemAnalyzer.new(root_path: root, target_version: "8.0.2").call
      dependencies = result[:dependencies].to_h { |dependency| [dependency[:name], dependency] }

      assert_equal :compatible, dependencies.fetch("devise")[:status]
      assert_equal :unknown, dependencies.fetch("sidekiq")[:status]
      assert_equal :warning, dependencies.fetch("legacy_gem")[:status]
      assert_includes dependencies.fetch("legacy_gem")[:message], "do not allow Rails 8.0"
      assert_equal :git, dependencies.fetch("internal_gem")[:source]
      assert_equal :warning, dependencies.fetch("internal_gem")[:status]
      assert_equal :path, dependencies.fetch("local_gem")[:source]
      assert_equal :warning, dependencies.fetch("local_gem")[:status]
      refute dependencies.key?("rails")
    end
  end

  def test_gem_analyzer_applies_compatibility_rules
    Dir.mktmpdir do |root|
      File.write(File.join(root, "Gemfile.lock"), sample_lockfile)
      File.write(
        File.join(root, "rules.yml"),
        <<~YAML
          gems:
            devise:
              rails:
                "8.0":
                  requirement: ">= 4.9.0"
                  status: compatible
                  message: "Known compatible version"
        YAML
      )
      repository = Railslift::GemCompatibilityRepository.new(path: File.join(root, "rules.yml"))

      result = Railslift::GemAnalyzer.new(
        root_path: root,
        target_version: "8.0",
        repository: repository
      ).call
      devise = result[:dependencies].find { |dependency| dependency[:name] == "devise" }

      assert_equal :warning, devise[:status]
      assert_includes devise[:message], "does not satisfy >= 4.9.0"
    end
  end

  def test_gem_analyzer_marks_a_satisfied_rule_as_compatible
    Dir.mktmpdir do |root|
      File.write(File.join(root, "Gemfile.lock"), sample_lockfile)
      File.write(
        File.join(root, "rules.yml"),
        <<~YAML
          gems:
            devise:
              rails:
                "8.0":
                  requirement: ">= 4.8.0"
                  status: compatible
                  message: "Known compatible version"
        YAML
      )
      repository = Railslift::GemCompatibilityRepository.new(path: File.join(root, "rules.yml"))

      result = Railslift::GemAnalyzer.new(
        root_path: root,
        target_version: "8.0",
        repository: repository
      ).call
      devise = result[:dependencies].find { |dependency| dependency[:name] == "devise" }

      assert_equal :compatible, devise[:status]
      assert_equal "Known compatible version", devise[:message]
      assert_equal 1, result[:summary][:compatible]
    end
  end

  def test_gem_analyzer_requires_a_lockfile
    Dir.mktmpdir do |root|
      error = assert_raises(Railslift::GemAnalyzer::MissingLockfile) do
        Railslift::GemAnalyzer.new(root_path: root, target_version: "8.0").call
      end

      assert_includes error.message, "Gemfile.lock was not found"
    end
  end

  def test_gems_command_prints_analysis
    Dir.mktmpdir do |root|
      File.write(File.join(root, "Gemfile.lock"), sample_lockfile)

      output, = capture_io do
        Dir.chdir(root) { Railslift::CLI.start(["gems", "--target", "8.0"]) }
      end

      assert_includes output, "Railslift Gem Analysis"
      assert_includes output, "✓ devise 4.8.1 [rubygems]"
      assert_includes output, "! internal_gem 1.0.0 [git]"
      assert_includes output, "Unknown: 1"
    end
  end

  def test_upgrade_planner_does_not_overshoot_a_patch_target
    result = Railslift::UpgradePlanner.new(
      current_version: "7.0.4.2",
      target_version: "8.0.2"
    ).call

    assert_equal "8.0", result[:steps].last[:to]
    refute_includes result[:steps], { from: "8.0", to: "8.1" }
  end

  def test_project_report_combines_deterministic_analysis
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".ruby-version"), "3.2.2\n")
      File.write(File.join(root, "Gemfile.lock"), report_lockfile)

      result = Railslift::ProjectReport.new(root_path: root, target_version: "8.0.2").call

      assert_equal 1, result[:schema_version]
      assert_equal "railslift", result[:generated_by][:name]
      assert_equal "7.0.8", result[:project][:rails_version]
      assert_equal "8.0", result[:plan][:steps].last[:to]
      assert result[:checks][:compatible]
      assert_equal 1, result[:summary][:gems_unknown]
    end
  end

  def test_report_command_prints_json_contract
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".ruby-version"), "3.2.2\n")
      File.write(File.join(root, "Gemfile.lock"), report_lockfile)

      output, = capture_io do
        Dir.chdir(root) do
          Railslift::CLI.start(["report", "--target", "8.0", "--format", "json"])
        end
      end
      report = JSON.parse(output)

      assert_equal 1, report["schema_version"]
      assert_equal "7.0.8", report.dig("project", "rails_version")
      assert_equal "8.0", report["target_rails_version"]
      assert_equal "8.0", report.dig("plan", "steps").last["to"]
      assert_equal true, report.dig("summary", "ruby_compatible")
    end
  end

  def test_report_command_prints_human_summary
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".ruby-version"), "3.1.4\n")
      File.write(File.join(root, "Gemfile.lock"), report_lockfile)

      output, = capture_io do
        Dir.chdir(root) { Railslift::CLI.start(["report", "--target", "8.0"]) }
      end

      assert_includes output, "Railslift Report"
      assert_includes output, "Current Rails: 7.0.8"
      assert_includes output, "- 7.2 → 8.0"
      assert_includes output, "Ruby: Upgrade required"
      assert_includes output, "Gems without compatibility evidence: 1"
    end
  end

  def test_project_report_requires_a_rails_project
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".ruby-version"), "3.2.2\n")

      error = assert_raises(Railslift::ProjectReport::MissingRails) do
        Railslift::ProjectReport.new(root_path: root, target_version: "8.0").call
      end

      assert_includes error.message, "Rails was not detected"
    end
  end

  def test_ai_provider_factory_builds_openai_adapter
    provider = Railslift::AI::ProviderFactory.build(
      name: "openai",
      api_key: "test-key",
      http_client: Object.new
    )

    assert_instance_of Railslift::AI::Providers::OpenAI, provider
  end

  def test_ai_provider_factory_rejects_unknown_provider
    error = assert_raises(Railslift::AI::Provider::ConfigurationError) do
      Railslift::AI::ProviderFactory.build(name: "unknown")
    end

    assert_includes error.message, "Unsupported AI provider"
  end

  def test_ai_provider_factory_accepts_registered_adapters
    adapter = Class.new(Railslift::AI::Provider) do
      def initialize(label:)
        @label = label
      end

      attr_reader :label
    end
    Railslift::AI::ProviderFactory.register("custom", adapter)

    provider = Railslift::AI::ProviderFactory.build(name: "custom", label: "local")

    assert_instance_of adapter, provider
    assert_equal "local", provider.label
  end

  def test_openai_adapter_requires_an_api_key
    error = assert_raises(Railslift::AI::Provider::ConfigurationError) do
      Railslift::AI::Providers::OpenAI.new(api_key: "")
    end

    assert_includes error.message, "OPENAI_API_KEY"
  end

  def test_openai_adapter_sends_structured_output_request
    http_client = fake_http_client(
      code: "200",
      body: JSON.generate(
        output: [
          {
            content: [
              {
                type: "output_text",
                text: JSON.generate(risk_level: "high", risks: ["Upgrade Ruby"])
              }
            ]
          }
        ]
      )
    )
    provider = Railslift::AI::Providers::OpenAI.new(
      api_key: "test-key",
      model: "test-model",
      http_client: http_client
    )
    schema = {
      type: "object",
      properties: {
        risk_level: { type: "string" },
        risks: { type: "array", items: { type: "string" } }
      },
      required: %w[risk_level risks],
      additionalProperties: false
    }

    result = provider.generate(
      input: { schema_version: 1 },
      schema: schema,
      instructions: "Analyze this Rails upgrade report."
    )
    request = http_client.requests.first
    payload = JSON.parse(request.body)

    assert_equal({ risk_level: "high", risks: ["Upgrade Ruby"] }, result)
    assert_equal "Bearer test-key", request["Authorization"]
    assert_equal "test-model", payload["model"]
    assert_equal "json_schema", payload.dig("text", "format", "type")
    assert_equal JSON.parse(JSON.generate(schema)), payload.dig("text", "format", "schema")
  end

  def test_openai_adapter_wraps_api_errors
    http_client = fake_http_client(
      code: "401",
      body: JSON.generate(error: { message: "Invalid API key" })
    )
    provider = Railslift::AI::Providers::OpenAI.new(
      api_key: "bad-key",
      http_client: http_client
    )

    error = assert_raises(Railslift::AI::Provider::RequestError) do
      provider.generate(input: {}, schema: {}, instructions: "Analyze")
    end

    assert_includes error.message, "Invalid API key"
  end

  def test_ai_analyzer_passes_report_and_schema_to_provider
    provider = Object.new
    provider.define_singleton_method(:generate) do |input:, schema:, instructions:|
      @request = { input: input, schema: schema, instructions: instructions }
      {
        risk_level: "high",
        summary: "Ruby must be upgraded.",
        risks: [],
        blockers: ["Ruby is incompatible"],
        recommended_steps: []
      }
    end
    provider.define_singleton_method(:request) { @request }
    report = { schema_version: 1, summary: { ruby_compatible: false } }

    result = Railslift::AI::Analyzer.new(provider: provider).call(report: report)

    assert_equal "high", result[:risk_level]
    assert_equal report, provider.request[:input]
    assert_equal false, provider.request[:schema][:additionalProperties]
    assert_includes provider.request[:instructions], "Do not claim that files were changed"
  end

  def test_analyze_command_prints_ai_recommendations
    analysis = {
      risk_level: "high",
      summary: "Ruby and one dependency block the upgrade.",
      risks: [
        {
          severity: "high",
          title: "Ruby version is incompatible",
          evidence: "Rails 8.0 requires Ruby 3.2.0 or newer.",
          recommendation: "Upgrade Ruby before Rails."
        }
      ],
      blockers: ["Upgrade Ruby"],
      recommended_steps: [
        {
          order: 1,
          action: "Upgrade Ruby",
          rationale: "Rails 8.0 requires Ruby 3.2.0 or newer."
        }
      ]
    }
    analyzer = Object.new
    analyzer.define_singleton_method(:call) { |**_arguments| analysis }

    Dir.mktmpdir do |root|
      File.write(File.join(root, ".ruby-version"), "3.1.4\n")
      File.write(File.join(root, "Gemfile.lock"), report_lockfile)

      output, = capture_io do
        Railslift::AI::Analyzer.stub(:new, ->(*) { analyzer }) do
          Dir.chdir(root) { Railslift::CLI.start(["analyze", "--target", "8.0"]) }
        end
      end

      assert_includes output, "Railslift AI Analysis"
      assert_includes output, "Risk level: High"
      assert_includes output, "Blockers:"
      assert_includes output, "[HIGH] Ruby version is incompatible"
      assert_includes output, "1. Upgrade Ruby"
    end
  end

  def test_analyze_command_prints_json
    analysis = {
      risk_level: "low",
      summary: "Ready to upgrade.",
      risks: [],
      blockers: [],
      recommended_steps: []
    }
    analyzer = Object.new
    analyzer.define_singleton_method(:call) { |**_arguments| analysis }

    Dir.mktmpdir do |root|
      File.write(File.join(root, ".ruby-version"), "3.2.2\n")
      File.write(File.join(root, "Gemfile.lock"), report_lockfile)

      output, = capture_io do
        Railslift::AI::Analyzer.stub(:new, ->(*) { analyzer }) do
          Dir.chdir(root) do
            Railslift::CLI.start(["analyze", "--target", "8.0", "--format", "json"])
          end
        end
      end

      assert_equal analysis, JSON.parse(output, symbolize_names: true)
    end
  end

  def test_upgrade_executor_previews_without_modifying_files
    Dir.mktmpdir do |root|
      write_upgrade_project(root)
      gemfile_path = File.join(root, "Gemfile")
      original = File.read(gemfile_path)

      result = Railslift::UpgradeExecutor.new(
        root_path: root,
        target_version: "7.1"
      ).call

      refute result[:applied]
      assert_equal 'gem "rails", "~> 7.0.4"', result[:gemfile_change][:before]
      assert_equal 'gem "rails", "~> 7.1.0"', result[:gemfile_change][:after]
      assert_equal original, File.read(gemfile_path)
    end
  end

  def test_upgrade_executor_applies_gemfile_and_bundle_update
    Dir.mktmpdir do |root|
      write_upgrade_project(root)
      runner = successful_upgrade_runner

      result = Railslift::UpgradeExecutor.new(
        root_path: root,
        target_version: "7.1",
        apply: true,
        runner: runner,
        runtime_version: "4.0.2"
      ).call

      assert result[:applied]
      assert_includes File.read(File.join(root, "Gemfile")), 'gem "rails", "~> 7.1.0"'
      assert_includes runner.commands, ["mise", "exec", "ruby@3.2.2", "--", "bundle", "update", "rails"]
    end
  end

  def test_upgrade_executor_restores_files_when_bundle_fails
    Dir.mktmpdir do |root|
      write_upgrade_project(root)
      gemfile_path = File.join(root, "Gemfile")
      lockfile_path = File.join(root, "Gemfile.lock")
      original_gemfile = File.read(gemfile_path)
      original_lockfile = File.read(lockfile_path)
      runner = successful_upgrade_runner(bundle_success: false)

      assert_raises(Railslift::UpgradeExecutor::CommandFailed) do
        Railslift::UpgradeExecutor.new(
          root_path: root,
          target_version: "7.1",
          apply: true,
          runner: runner,
          runtime_version: "4.0.2"
        ).call
      end

      assert_equal original_gemfile, File.read(gemfile_path)
      assert_equal original_lockfile, File.read(lockfile_path)
    end
  end

  def test_upgrade_executor_rejects_multi_minor_jump
    Dir.mktmpdir do |root|
      write_upgrade_project(root)

      assert_raises(Railslift::UpgradeExecutor::UnsupportedTarget) do
        Railslift::UpgradeExecutor.new(
          root_path: root,
          target_version: "8.0"
        ).call
      end
    end
  end

  def test_upgrade_executor_stops_before_changes_when_project_ruby_is_unavailable
    Dir.mktmpdir do |root|
      write_upgrade_project(root)
      gemfile_path = File.join(root, "Gemfile")
      original = File.read(gemfile_path)
      runner = successful_upgrade_runner(runtime_available: false)

      error = assert_raises(Railslift::UpgradeExecutor::RuntimeUnavailable) do
        Railslift::UpgradeExecutor.new(
          root_path: root,
          target_version: "7.1",
          apply: true,
          runner: runner,
          runtime_version: "4.0.2"
        ).call
      end

      assert_includes error.message, "mise install ruby@3.2.2"
      assert_equal original, File.read(gemfile_path)
      refute_includes runner.commands, ["mise", "exec", "ruby@3.2.2", "--", "bundle", "update", "rails"]
    end
  end

  def test_upgrade_command_defaults_to_preview
    Dir.mktmpdir do |root|
      write_upgrade_project(root)

      output, = capture_io do
        Dir.chdir(root) { Railslift::CLI.start(["upgrade", "--target", "7.1"]) }
      end

      assert_includes output, "Railslift Upgrade"
      assert_includes output, "Preview only. No files were modified."
      assert_includes output, 'gem "rails", "~> 7.1.0"'
    end
  end

  def test_assisted_upgrade_runs_app_update_and_stops_when_tests_pass
    Dir.mktmpdir do |root|
      write_assisted_upgrade_project(root)
      runner = assisted_upgrade_runner(test_results: [true])
      approvals = [true]

      result = Railslift::AssistedUpgrade.new(
        root_path: root,
        target_version: "7.2",
        runner: runner,
        fixer: Object.new,
        approve: ->(_question) { approvals.shift }
      ).call

      assert_equal :tests_passed, result[:status]
      assert_includes runner.commands, [:run, "mise", "exec", "ruby@3.2.2", "--", "bin/rails", "app:update"]
      assert_includes runner.commands, [:capture, "mise", "exec", "ruby@3.2.2", "--", "bin/rails", "test"]
    end
  end

  def test_assisted_upgrade_applies_ai_patch_and_reruns_tests
    Dir.mktmpdir do |root|
      write_assisted_upgrade_project(root)
      runner = assisted_upgrade_runner(test_results: [false, true])
      fixer = Object.new
      fixer.define_singleton_method(:call) do |context:|
        {
          summary: "Fix deprecated configuration",
          patch: "--- a/config/application.rb\n+++ b/config/application.rb\n"
        }
      end
      approvals = [true, true]

      result = Railslift::AssistedUpgrade.new(
        root_path: root,
        target_version: "7.2",
        runner: runner,
        fixer: fixer,
        approve: ->(_question) { approvals.shift }
      ).call

      assert_equal :fixed, result[:status]
      assert runner.commands.any? { |command| command[0, 3] == [:capture, "git", "apply"] }
      assert_equal 2, runner.test_runs
    end
  end

  def test_assisted_upgrade_requires_clean_worktree
    Dir.mktmpdir do |root|
      write_assisted_upgrade_project(root)
      runner = assisted_upgrade_runner(clean: false)

      error = assert_raises(Railslift::AssistedUpgrade::DirtyWorktree) do
        Railslift::AssistedUpgrade.new(
          root_path: root,
          target_version: "7.2",
          runner: runner,
          fixer: Object.new,
          approve: ->(_question) { true }
        ).call
      end

      assert_includes error.message, "Commit or stash"
    end
  end

  private

  FakeUpgradeResult = Data.define(:success, :output)

  def successful_upgrade_runner(bundle_success: true, runtime_available: true)
    runner = Object.new
    runner.define_singleton_method(:commands) { @commands ||= [] }
    runner.define_singleton_method(:capture) do |*command, chdir:|
      commands << command
      case command
      when ["git", "rev-parse", "--is-inside-work-tree"]
        FakeUpgradeResult.new(success: true, output: "true\n")
      when ["git", "status", "--porcelain"]
        FakeUpgradeResult.new(success: true, output: "")
      when ["mise", "--version"]
        FakeUpgradeResult.new(success: true, output: "mise 2026.1.0\n")
      when ["mise", "exec", "ruby@3.2.2", "--", "ruby", "-e", "print RUBY_VERSION"]
        FakeUpgradeResult.new(
          success: runtime_available,
          output: runtime_available ? "3.2.2" : "ruby 3.2.2 is not installed"
        )
      when ["mise", "exec", "ruby@3.2.2", "--", "bundle", "update", "rails"]
        FakeUpgradeResult.new(success: bundle_success, output: bundle_success ? "Updated\n" : "Failure\n")
      end
    end
    runner
  end

  def write_upgrade_project(root)
    File.write(File.join(root, ".ruby-version"), "3.2.2\n")
    File.write(File.join(root, "Gemfile"), <<~RUBY)
      source "https://rubygems.org"

      gem "rails", "~> 7.0.4"
      gem "sidekiq"
    RUBY
    File.write(File.join(root, "Gemfile.lock"), report_lockfile)
  end

  def write_assisted_upgrade_project(root)
    File.write(File.join(root, ".ruby-version"), "3.2.2\n")
    FileUtils.mkdir_p(File.join(root, "config"))
    File.write(File.join(root, "config/application.rb"), "class Application\nend\n")
    File.write(File.join(root, "Gemfile"), 'gem "rails", "~> 7.2.0"' + "\n")
    File.write(File.join(root, "Gemfile.lock"), report_lockfile.gsub("7.0.8", "7.2.2"))
  end

  def assisted_upgrade_runner(test_results: [], clean: true)
    runner = Object.new
    runner.define_singleton_method(:commands) { @commands ||= [] }
    runner.define_singleton_method(:test_runs) { @test_runs || 0 }
    runner.define_singleton_method(:run) do |*command, chdir:|
      commands << [:run, *command]
      FakeUpgradeResult.new(success: true, output: "")
    end
    runner.define_singleton_method(:capture) do |*command, chdir:|
      commands << [:capture, *command]
      case command
      when ["git", "rev-parse", "--is-inside-work-tree"]
        FakeUpgradeResult.new(success: true, output: "true\n")
      when ["git", "status", "--porcelain"]
        FakeUpgradeResult.new(success: true, output: clean ? "" : " M Gemfile\n")
      when ["git", "diff", "--", "."]
        FakeUpgradeResult.new(success: true, output: "diff --git a/config/application.rb b/config/application.rb\n")
      else
        if command.last(2) == ["bin/rails", "test"]
          @test_runs = (@test_runs || 0) + 1
          success = test_results.shift
          FakeUpgradeResult.new(
            success: success,
            output: success ? "0 failures\n" : "config/application.rb:1: failure\n"
          )
        elsif command[0, 2] == ["git", "apply"]
          FakeUpgradeResult.new(success: true, output: "")
        end
      end
    end
    runner
  end

  def fake_http_client(code:, body:)
    response_class = code.start_with?("2") ? Net::HTTPOK : Net::HTTPUnauthorized
    response = response_class.new("1.1", code, "")
    response.instance_variable_set(:@read, true)
    response.body = body

    client = Object.new
    client.define_singleton_method(:requests) { @requests ||= [] }
    client.define_singleton_method(:start) do |_host, _port, use_ssl:, &block|
      http = Object.new
      http.define_singleton_method(:request) do |request|
        client.requests << request
        response
      end
      block.call(http)
    end
    client
  end

  def report_lockfile
    <<~LOCKFILE
      GEM
        remote: https://rubygems.org/
        specs:
          actionpack (7.0.8)
          rails (7.0.8)
            actionpack (= 7.0.8)
            railties (= 7.0.8)
          railties (7.0.8)
          sidekiq (7.3.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        rails
        sidekiq

      BUNDLED WITH
         4.0.6
    LOCKFILE
  end

  def sample_lockfile
    <<~LOCKFILE
      GIT
        remote: https://example.com/internal_gem.git
        revision: abc123
        specs:
          internal_gem (1.0.0)

      PATH
        remote: components/local_gem
        specs:
          local_gem (0.2.0)

      GEM
        remote: https://rubygems.org/
        specs:
          actionpack (8.0.0)
          devise (4.8.1)
            railties (>= 4.1.0)
          legacy_gem (1.0.0)
            railties (< 8.0)
          rails (8.0.0)
            actionpack (= 8.0.0)
            railties (= 8.0.0)
          railties (8.0.0)
          sidekiq (7.3.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        devise
        internal_gem!
        legacy_gem
        local_gem!
        rails
        sidekiq

      BUNDLED WITH
         4.0.6
    LOCKFILE
  end
end
