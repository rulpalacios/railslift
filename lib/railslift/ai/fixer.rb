# frozen_string_literal: true

require_relative "provider_factory"

module Railslift
  module AI
    class Fixer
      INSTRUCTIONS = <<~TEXT.freeze
        Fix the failing Rails upgrade using only the supplied test output, git diff,
        and file contents. Return a minimal unified diff that can be applied with
        git apply. Do not modify dependencies, generated lockfiles, secrets, or
        unrelated files. If there is not enough evidence for a safe patch, return
        an empty patch and explain why.
      TEXT

      SCHEMA = {
        type: "object",
        properties: {
          summary: { type: "string" },
          patch: { type: "string" }
        },
        required: %w[summary patch],
        additionalProperties: false
      }.freeze

      def initialize(provider: ProviderFactory.build)
        @provider = provider
      end

      def call(context:)
        @provider.generate(
          input: context,
          schema: SCHEMA,
          instructions: INSTRUCTIONS
        )
      end
    end
  end
end
