# frozen_string_literal: true

require "test_helper"

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
end
