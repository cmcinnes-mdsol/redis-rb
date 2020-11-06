# frozen_string_literal: true

require_relative "registry"
require_relative "../errors"
require "hiredis/connection"
require "timeout"

class Redis
  module Connection
    class Hiredis
      def self.connect(config)
        connection = ::Hiredis::Connection.new
        connect_timeout = (config.fetch(:connect_timeout, 0) * 1_000_000).to_i

        if config[:scheme] == "unix"
          connection.connect_unix(config[:path], connect_timeout)
        elsif config[:scheme] == "rediss" || config[:ssl]
          connection.connect(config[:host], config[:port], connect_timeout)

          # I don't think we actually need these, but let's find out.
          ca, cert, key, servername = Array.new(4) { nil }
          connection.secure(ca, cert, key, servername)
        else
          connection.connect(config[:host], config[:port], connect_timeout)
        end

        instance = new(connection)
        instance.timeout = config[:read_timeout]
        instance
      rescue Errno::ETIMEDOUT
        raise TimeoutError
      end

      def initialize(connection)
        @connection = connection
      end

      def connected?
        @connection&.connected?
      end

      def timeout=(timeout)
        # Hiredis works with microsecond timeouts
        @connection.timeout = Integer(timeout * 1_000_000)
      end

      def disconnect
        @connection.disconnect
        @connection = nil
      end

      def write(command)
        @connection.write(command.flatten(1))
      rescue Errno::EAGAIN
        raise TimeoutError
      end

      def read
        reply = @connection.read
        reply = CommandError.new(reply.message) if reply.is_a?(RuntimeError)
        reply
      rescue Errno::EAGAIN
        raise TimeoutError
      rescue RuntimeError => err
        raise ProtocolError, err.message
      end
    end
  end
end

Redis::Connection.drivers << Redis::Connection::Hiredis
