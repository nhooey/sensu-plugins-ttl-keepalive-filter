#!/usr/bin/env ruby

require 'json'
require 'rest-client'

require 'sensu/api/process'
require 'sensu/daemon'

module Sensu::Extension

  class TtlKeepaliveFilter < Filter
    include Sensu::Daemon

    def name
      'filter-ttl-keepalive'
    end

    def description
      'Filters failed TTL events when the client is failing its keepalive check'
    end

    def definition
      {
        type: 'extension',
        name: 'filter-ttl-keepalive',
      }
    end

    def initialize
      super

      @api_config = @settings[:api]
      @api_host = @settings[:api][:host]
      @api_port = @settings[:api][:port]
      @api_user = @settings[:api][:user]
      @api_pass = @settings[:api][:password]
    end

    def logger
      Sensu::Logger.get
    end

    def safe_run(event)
      output = ''
      status = 1

      @logger.info("#{name}: Running filtering on event: #{event}")

      check_failure = event[:check][:status].to_i != 0
      check_failure_type_ttl = event[:check][:output].start_with?('Last check execution was')

      if check_failure && check_failure_type_ttl
        client_name = event[:client][:name]
        check_name = :keepalive
        check_endpoint = "http://#{@api_user}:#{@api_pass}@#{@api_host}:#{@api_port}/results/#{client_name}/#{check_name}"

        begin
          logger.info("Checking client in API: #{check_endpoint}")
          response = RestClient.get(check_endpoint, {:accept => :json})
        rescue => e
          @logger.error("#{name}: API request: '#{check_endpoint}' failed: #{e}")
        end

        @logger.info("#{name}: API Response: #{response}")

        if !response.nil?
          begin
            check_data = JSON.parse(response.body)
          rescue JSON::ParserError
            @logger.error("#{name}: Failed to parse API JSON response: #{response}")
          end

          if check_data['check']['status'].to_i != 0
            output = 'Filtering failed TTL check result because client is failing keepalive check.'
            status = 0
            @logger.info("#{name}: Filtering: '#{client_name}/#{check_name}' : '#{output}'")
          end
        end
      end

      yield output, status
    end
  end
end
