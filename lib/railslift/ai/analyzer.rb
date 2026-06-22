# frozen_string_literal: true

require_relative "provider_factory"

module Railslift
  module AI
    class Analyzer
      INSTRUCTIONS = <<~TEXT.freeze
        Analyze the Rails upgrade report provided by Railslift.
        Base every conclusion only on the deterministic report.
        Prioritize blockers, Ruby requirements, incompatible gems, unknown dependencies,
        and the safest order for the upgrade.
        Do not claim that files were changed or commands were executed.
        Keep recommendations concrete, concise, and specific to the report.
      TEXT

      SCHEMA = {
        type: "object",
        properties: {
          risk_level: {
            type: "string",
            enum: %w[low medium high]
          },
          summary: {
            type: "string"
          },
          risks: {
            type: "array",
            items: {
              type: "object",
              properties: {
                severity: {
                  type: "string",
                  enum: %w[low medium high]
                },
                title: {
                  type: "string"
                },
                evidence: {
                  type: "string"
                },
                recommendation: {
                  type: "string"
                }
              },
              required: %w[severity title evidence recommendation],
              additionalProperties: false
            }
          },
          blockers: {
            type: "array",
            items: {
              type: "string"
            }
          },
          recommended_steps: {
            type: "array",
            items: {
              type: "object",
              properties: {
                order: {
                  type: "integer"
                },
                action: {
                  type: "string"
                },
                rationale: {
                  type: "string"
                }
              },
              required: %w[order action rationale],
              additionalProperties: false
            }
          }
        },
        required: %w[risk_level summary risks blockers recommended_steps],
        additionalProperties: false
      }.freeze

      def initialize(provider: ProviderFactory.build)
        @provider = provider
      end

      def call(report:)
        @provider.generate(
          input: report,
          schema: SCHEMA,
          instructions: INSTRUCTIONS
        )
      end
    end
  end
end
