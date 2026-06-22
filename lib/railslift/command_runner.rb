# frozen_string_literal: true

require "open3"

module Railslift
  class CommandRunner
    Result = Data.define(:success, :output)

    def capture(*command, chdir:)
      stdout, stderr, status = Open3.capture3(*command, chdir: chdir)
      Result.new(success: status.success?, output: "#{stdout}#{stderr}")
    rescue Errno::ENOENT => error
      Result.new(success: false, output: error.message)
    end

    def run(*command, chdir:)
      Result.new(success: system(*command, chdir: chdir), output: "")
    rescue Errno::ENOENT => error
      Result.new(success: false, output: error.message)
    end
  end
end
