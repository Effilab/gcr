require "greetings_services_pb"

module Greetings
  class Server < Service
    ADDRESS = "127.0.0.1:5567"

    def self.start
      raise "server already running" if running?

      @rpc_server = GRPC::RpcServer.new
      @rpc_server.add_http2_port(ADDRESS, :this_port_is_insecure)
      @rpc_server.handle(new)
      @server_thread = Thread.new { @rpc_server.run }
      @rpc_server.wait_till_running
    end

    def self.stop
      raise "server not running" unless running?

      @rpc_server.stop
      @server_thread.join
      @rpc_server = nil
      @server_thread = nil
    end

    def self.running?
      !!@server_thread&.alive?
    end

    def hello(req, _call)
      HelloResponse.new(
        greeting: "resp #{increment_counter} — hello #{req.name}"
      )
    end

    def increment_counter
      if defined?(@counter)
        @counter += 1
      else
        @counter = 0
      end

      return @counter
    end
  end
end
