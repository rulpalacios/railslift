# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "../provider"

module Railslift
  module AI
    module Providers
      class OpenAI < Provider
        DEFAULT_BASE_URL = "https://api.openai.com/v1"
        DEFAULT_MODEL = "gpt-5.5"

        def initialize(
          api_key: ENV["OPENAI_API_KEY"],
          model: ENV.fetch("RAILSLIFT_AI_MODEL", DEFAULT_MODEL),
          base_url: ENV.fetch("OPENAI_BASE_URL", DEFAULT_BASE_URL),
          http_client: Net::HTTP
        )
          raise ConfigurationError, "OPENAI_API_KEY is not configured" if api_key.nil? || api_key.empty?

          @api_key = api_key
          @model = model
          @base_url = base_url
          @http_client = http_client
        end

        def generate(input:, schema:, instructions:)
          response = post_response(
            model: @model,
            instructions: instructions,
            input: JSON.generate(input),
            text: {
              format: {
                type: "json_schema",
                name: "railslift_analysis",
                strict: true,
                schema: schema
              }
            }
          )

          JSON.parse(extract_output_text(response), symbolize_names: true)
        rescue JSON::ParserError => error
          raise InvalidResponse, "OpenAI returned invalid JSON: #{error.message}"
        end

        private

        def post_response(payload)
          uri = URI.join("#{@base_url}/", "responses")
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{@api_key}"
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(payload)

          response = @http_client.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
            http.request(request)
          end

          body = JSON.parse(response.body)
          return body if response.is_a?(Net::HTTPSuccess)

          message = body.dig("error", "message") || "HTTP #{response.code}"
          raise RequestError, "OpenAI request failed: #{message}"
        rescue JSON::ParserError => error
          raise InvalidResponse, "OpenAI returned an unreadable response: #{error.message}"
        rescue SystemCallError, SocketError, Timeout::Error => error
          raise RequestError, "OpenAI request failed: #{error.message}"
        end

        def extract_output_text(response)
          response.fetch("output").each do |item|
            item.fetch("content", []).each do |content|
              return content.fetch("text") if content["type"] == "output_text"

              if content["type"] == "refusal"
                raise InvalidResponse, "OpenAI refused the analysis: #{content["refusal"]}"
              end
            end
          end

          raise InvalidResponse, "OpenAI response did not contain output text"
        rescue KeyError => error
          raise InvalidResponse, "OpenAI response is missing #{error.key}"
        end
      end
    end
  end
end
