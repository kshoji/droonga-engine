# Copyright (C) 2014 Droonga Project
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License version 2.1 as published by the Free Software Foundation.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require "json"

require "droonga/path"
require "droonga/serf"
require "droonga/node_status"
require "droonga/catalog_generator"
require "droonga/catalog_modifier"
require "droonga/catalog_fetcher"
require "droonga/data_absorber"
require "droonga/safe_file_writer"

module Droonga
  module Command
    class SerfEventHandler
      class << self
        def run
          new.run
        end
      end

      def initialize
        @serf = ENV["SERF"] || Serf.path
        @serf_rpc_address = ENV["SERF_RPC_ADDRESS"] || "127.0.0.1:7373"
        @serf_name = ENV["SERF_SELF_NAME"]
        @response = {
          "log" => []
        }
      end

      def run
        parse_event
        unless should_process?
          log(" => ignoring event not for me")
          output_response
          return true
        end

        process_event
        output_live_nodes
        output_response
        true
      end

      private
      def parse_event
        @event_name = ENV["SERF_EVENT"]
        @payload = nil
        case @event_name
        when "user"
          @event_sub_name = ENV["SERF_USER_EVENT"]
          @payload = JSON.parse($stdin.gets)
          log("event sub name = #{@event_sub_name}")
        when "query"
          @event_sub_name = ENV["SERF_QUERY_NAME"]
          @payload = JSON.parse($stdin.gets)
          log("event sub name = #{@event_sub_name}")
        when "member-join", "member-leave", "member-update", "member-reap"
          output_live_nodes
        end
      end

      def target_node
        @payload && @payload["node"]
      end

      def for_me?
        target_node == @serf_name
      end

      def should_process?
        for_me? or @payload.nil? or not @payload.include?("node")
      end

      def process_event
        case @event_sub_name
        when "change_role"
          NodeStatus.set(:role, @payload["role"])
        when "report_status"
          report_status
        when "join"
          join
        when "set_replicas"
          set_replicas
        when "add_replicas"
          add_replicas
        when "remove_replicas"
          remove_replicas
        when "absorb_data"
          absorb_data
        end
      end

      def output_response
        puts JSON.generate(@response)
      end

      def host
        @serf_name.split(":").first
      end

      def given_hosts
        hosts = @payload["hosts"]
        return nil unless hosts
        hosts = [hosts] if hosts.is_a?(String)
        hosts
      end

      def report_status
        @response["value"] = NodeStatus.get(@payload["key"])
      end

      def join
        type = @payload["type"]
        log("type = #{type}")
        case type
        when "replica"
          join_as_replica
        end
      end

      def join_as_replica
        source_node         = @payload["source"]
        source_node_port    = @payload["port"]
        joining_node        = @payload["node"]
        tag                 = @payload["tag"]
        dataset_name        = @payload["dataset"]
        required_params = [
          source_node,
          source_node_port,
          joining_node,
          dataset_name,
        ]
        return unless required_params.all?

        log("source_node  = #{source_node}")

        source_host  = source_node.split(":").first
        joining_host = joining_node.split(":").first

        fetcher = CatalogFetcher.new(:host          => source_host,
                                     :port          => source_node_port,
                                     :tag           => tag,
                                     :receiver_host => joining_host)
        catalog = fetcher.fetch(:dataset => dataset_name)

        generator = CatalogGenerator.new
        generator.load(catalog)
        dataset = generator.dataset_for_host(source_host) ||
                    generator.dataset_for_host(host)
        return unless dataset

        # restart self with the fetched catalog.
        SafeFileWriter.write(Path.catalog, JSON.pretty_generate(catalog))

        tag          = dataset.replicas.tag
        port         = dataset.replicas.port
        other_hosts  = dataset.replicas.hosts

        log("dataset = #{dataset_name}")
        log("port    = #{port}")
        log("tag     = #{tag}")

        if @payload["copy"]
          log("starting to copy data from #{source_host}")

          CatalogModifier.modify do |modifier|
            modifier.datasets[dataset_name].replicas.hosts = [host]
          end
          sleep(5) #TODO: wait for restart. this should be done more safely, to avoid starting of absorbing with old catalog.json.

          status = NodeStatus.new
          status.set(:absorbing, true)
          DataAbsorber.absorb(:dataset          => dataset_name,
                              :source_host      => source_host,
                              :destination_host => host,
                              :port             => port,
                              :tag              => tag)
          status.delete(:absorbing)
          sleep(1)
        end

        log("joining to the cluster: update myself")

        CatalogModifier.modify do |modifier|
          modifier.datasets[dataset_name].replicas.hosts += other_hosts
          modifier.datasets[dataset_name].replicas.hosts.uniq!
        end
      end

      def set_replicas
        dataset = @payload["dataset"]
        return unless dataset

        hosts = given_hosts
        return unless hosts

        log("new replicas: #{hosts.join(",")}")

        CatalogModifier.modify do |modifier|
          modifier.datasets[dataset].replicas.hosts = hosts
        end
      end

      def add_replicas
        dataset = @payload["dataset"]
        return unless dataset

        hosts = given_hosts
        return unless hosts

        hosts -= [host]
        return if hosts.empty?

        log("adding replicas: #{hosts.join(",")}")

        CatalogModifier.modify do |modifier|
          modifier.datasets[dataset].replicas.hosts += hosts
          modifier.datasets[dataset].replicas.hosts.uniq!
        end
      end

      def remove_replicas
        dataset = @payload["dataset"]
        return unless dataset

        hosts = given_hosts
        return unless hosts

        log("removing replicas: #{hosts.join(",")}")

        CatalogModifier.modify do |modifier|
          modifier.datasets[dataset].replicas.hosts -= hosts
        end
      end

      def absorb_data
        source = @payload["source"]
        return unless source

        log("start to absorb data from #{source}")

        dataset_name = @payload["dataset"]
        port         = @payload["port"]
        tag          = @payload["tag"]

        if dataset_name.nil? or port.nil? or tag.nil?
          current_catalog = JSON.parse(Path.catalog.read)
          generator = CatalogGenerator.new
          generator.load(current_catalog)

          dataset = generator.dataset_for_host(source)
          return unless dataset

          dataset_name = dataset.name
          port = dataset.replicas.port
          tag  = dataset.replicas.tag
        end

        log("dataset = #{dataset_name}")
        log("port    = #{port}")
        log("tag     = #{tag}")

        status = NodeStatus.new
        status.set(:absorbing, true)
        DataAbsorber.absorb(:dataset          => dataset_name,
                            :source_host      => source,
                            :destination_host => host,
                            :port             => port,
                            :tag              => tag,
                            :client           => "droonga-send")
        status.delete(:absorbing)
      end

      def live_nodes
        Serf.live_nodes(@serf_name)
      end

      def output_live_nodes
        path = Path.live_nodes
        nodes = live_nodes
        file_contents = JSON.pretty_generate(nodes)
        SafeFileWriter.write(path, file_contents)
      end

      def log(message)
        @response["log"] << message
      end
    end
  end
end
