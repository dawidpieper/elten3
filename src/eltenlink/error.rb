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
