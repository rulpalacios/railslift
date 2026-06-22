# frozen_string_literal: true

require "test_helper"
require "tmpdir"

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

  private

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
