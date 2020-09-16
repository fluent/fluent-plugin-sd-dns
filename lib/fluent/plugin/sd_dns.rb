#
# Fluentd
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

require 'socket'

require 'fluent/plugin_helper'
require 'fluent/plugin/service_discovery'

module Fluent
  module Plugin
    class DnsServiceDiscovery < ServiceDiscovery
      include PluginHelper::Mixin

      Plugin.register_sd('dns', self)

      helpers :timer

      desc 'Ignore DNS related error or not'
      config_param :ignore_dns_error, :bool, default: false
      desc 'Interval to refresh service list'
      config_param :interval, :time, default: nil

      config_section :entry, param_name: :entry_configs, required: true, multi: true do
        desc 'Hostname for service lookup'
        config_param :host, :string
        desc 'Port of service'
        config_param :port, :integer
        desc 'Specify the address family for returned address'
        config_param :address_family, default: nil do |val|
          case val.downcase
          when 'ipv4'
            Socket::Constants::AF_INET
          when 'ipv6'
            Socket::Constants::AF_INET6
          else
            raise Fluent::ConfigError, "Unsupported parameter value: #{val}"
          end
        end
        desc 'The shared_key for authentication per host'
        config_param :shared_key, :string, default: nil, secret: true
        desc 'The username for authentication per host'
        config_param :username, :string, default: ''
        desc 'The password for authentication per host'
        config_param :password, :string, default: '', secret: true
        desc 'The load balancing weight per host'
        config_param :weight, :integer, default: 60
      end

      def configure(conf)
        super
        @services = fetch_services_from_dns
      end

      def start(queue)
        if @interval
          timer_execute(:"sd_dns_refresh", @interval) do
            refresh_service_list(queue)
          end
        else
          refresh_service_list(queue)
        end

        super()
      end

      private

      def refresh_service_list(queue)
        old_services = @services
        new_services = begin
                         fetch_services_from_dns
                       rescue => e
                         @log.error("sd_dns: #{e}")
                         return
                       end

        if new_services.nil? || new_services.empty?
          return
        end

        diff = []
        join = new_services - old_services
        # Need service_in first to guarantee that server exist at least one all time.
        join.each do |j|
          diff << ServiceDiscovery.service_in_msg(j)
        end

        drain = old_services - new_services
        drain.each do |d|
          diff << ServiceDiscovery.service_out_msg(d)
        end

        @services = new_services

        diff.each do |a|
          queue.push(a)
        end
      end

      def fetch_services_from_dns
        service_list = []
        @entry_configs.each { |conf|
          ai_list = begin
                      Socket.getaddrinfo(conf.host, conf.port, conf.address_family, Socket::SOCK_STREAM)
                    rescue => e
                      if @ignore_dns_error
                        @log.warn "failed to get service list from #{conf.host}", error: e
                        next
                      else
                        raise
                      end
                    end
          ai_list.each_with_index { |ai, i|
            name = "#{i}-#{conf.host}"
            service_list << Service.new(:dns, ai[3], ai[1], name, conf.weight, false, conf.username, conf.password, conf.shared_key)
          }
        }
        service_list
      end
    end
  end
end
