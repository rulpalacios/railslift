# frozen_string_literal: true

require_relative "providers/openai"

module Railslift
  module AI
    class ProviderFactory
      @providers = {
        "openai" => Providers::OpenAI
      }

      def self.build(name: ENV.fetch("RAILSLIFT_AI_PROVIDER", "openai"), **options)
        provider = @providers[name.to_s.downcase]
        raise Provider::ConfigurationError, "Unsupported AI provider: #{name}" unless provider

        provider.new(**options)
      end

      def self.register(name, provider)
        @providers[name.to_s.downcase] = provider
      end
    end
  end
end
