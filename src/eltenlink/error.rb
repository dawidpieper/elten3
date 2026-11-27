# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  class Error < StandardError
    PREDEFINED = {
      "network_error" => "Network error",
      "timeout" => "Request timed out",
      "cancelled" => "Request cancelled",
      "invalid_json" => "Invalid JSON response",
      "api_error" => "API request failed"
    }.freeze

    attr_reader :code, :module_name, :response

    def initialize(message = nil, code: nil, module_name: nil, response: nil)
      @code = code
      @module_name = module_name
      @response = response
      super(message || self.class.message_for(code, module_name))
    end

    def details
      error_payload["details"]
    end

    def wordpress_reason
      info = details
      return unless info.is_a?(Hash)
      return info["wordpress_code"] if info["wordpress_code"]

      "HTTP #{info["wordpress_status"]}" if info["wordpress_status"]
    end

    def retry_after
      value = error_payload["retry_after"] || (details["retry_after"] if details.is_a?(Hash))
      value.nil? ? nil : value.to_f
    end

    def status
      error_payload["status"]
    end

    def error_payload
      error = @response["error"] if @response.is_a?(Hash)
      error.is_a?(Hash) ? error : {}
    end
    private :error_payload

    def self.message_for(code, module_name = nil)
      text = PREDEFINED[code.to_s] || "Server returned error #{code}"
      module_name == nil ? text : "#{text} (#{module_name})"
    end

    def self.network(module_name: nil)
      new(message_for("network_error", module_name), code: "network_error", module_name: module_name)
    end

    def self.timeout(module_name: nil)
      new(message_for("timeout", module_name), code: "timeout", module_name: module_name)
    end

    def self.cancelled(module_name: nil)
      new(message_for("cancelled", module_name), code: "cancelled", module_name: module_name)
    end
  end
end
