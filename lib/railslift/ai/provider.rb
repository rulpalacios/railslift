# frozen_string_literal: true

module Railslift
  module AI
    class Provider
      class Error < StandardError; end
      class ConfigurationError < Error; end
      class RequestError < Error; end
      class InvalidResponse < Error; end

      def generate(input:, schema:, instructions:)
        raise NotImplementedError, "#{self.class} must implement #generate"
      end
    end
  end
end
