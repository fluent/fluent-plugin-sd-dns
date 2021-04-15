require 'rr'
require 'test/unit'
require 'test/unit/rr'
require 'fileutils'
require 'flexmock/test_unit'

require 'fluent/env'
require 'fluent/test'
require 'fluent/plugin/sd_dns'

def ipv6_enabled?
  require 'socket'

  begin
    TCPServer.open("::1", 0)
    true
  rescue
    false
  end
end

class DnsServiceDiscoveryTest < ::Test::Unit::TestCase
  def parse_config(conf)
    Fluent::Config.parse(conf, "(test)", "(test_dir)", true)
  end

  def config(param: nil, af: 'ipv4')
    %[
      @type dns
      <entry>
        host localhost
        port 80
        address_family #{af}
        #{param}
      </entry>
    ]
  end

  setup do
    @sd_dns = Fluent::Plugin::DnsServiceDiscovery.new
  end

  sub_test_case '#configure with IPv4' do
    test 'set services' do
      @sd_dns.configure(parse_config(config))
      assert_equal Fluent::Plugin::ServiceDiscovery::Service.new(:dns, '127.0.0.1', 80, '0-localhost', 60, false, '', '', nil), @sd_dns.services[0]
    end

    test 'set services with auth settings' do
      @sd_dns.configure(parse_config(config(param: %[
        shared_key test_key
        username test_user
        password test_pass
      ])))
      assert_equal Fluent::Plugin::ServiceDiscovery::Service.new(:dns, '127.0.0.1', 80, '0-localhost', 60, false, 'test_user', 'test_pass', 'test_key'), @sd_dns.services[0]
    end

    test 'set services with multiple <entry>' do
      @sd_dns.configure(parse_config(%[
        @type dns
        <entry>
          host localhost
          port 80
          address_family ipv4
        </entry>
        <entry>
          host localhost
          port 81
          address_family ipv4
        </entry>
        <entry>
          host localhost
          port 82
          address_family ipv4
        </entry>
      ]))
      services = @sd_dns.services.sort_by {|e| e.name }
      assert_equal Fluent::Plugin::ServiceDiscovery::Service.new(:dns, '127.0.0.1', 80, '0-localhost', 60, false, '', '', nil), services[0]
      assert_equal Fluent::Plugin::ServiceDiscovery::Service.new(:dns, '127.0.0.1', 81, '0-localhost', 60, false, '', '', nil), services[1]
      assert_equal Fluent::Plugin::ServiceDiscovery::Service.new(:dns, '127.0.0.1', 82, '0-localhost', 60, false, '', '', nil), services[2]
    end

    test 'raise an error for no <entry>' do
      assert_raise(Fluent::ConfigError) {
        @sd_dns.configure(parse_config(%[@type dns]))
      }
    end
  end

  sub_test_case '#configure with IPv6 enabled' do
    test 'set services' do
      omit "IPv6 is not supported on this environment" unless ipv6_enabled?

      @sd_dns.configure(parse_config(config(af: 'ipv6')))
      assert_equal Fluent::Plugin::ServiceDiscovery::Service.new(:dns, '::1', 80, '0-localhost', 60, false, '', '', nil), @sd_dns.services[0]
    end

    test 'set services with unspecified address family' do
      omit "IPv6 is not supported on this environment" unless ipv6_enabled?

      @sd_dns.configure(parse_config(%[
        @type dns
        <entry>
          host localhost
          port 80
        </entry>
      ]))
      assert_equal 2, @sd_dns.services.size
      assert_equal Fluent::Plugin::ServiceDiscovery::Service.new(:dns, '::1', 80, '0-localhost', 60, false, '', '', nil), @sd_dns.services[0]
      assert_equal Fluent::Plugin::ServiceDiscovery::Service.new(:dns, '127.0.0.1', 80, '1-localhost', 60, false, '', '', nil), @sd_dns.services[1]
    end
  end

  sub_test_case 'failure cases' do
    test 'getaddrinfo raises an error' do
      stub(Socket).getaddrinfo('localhost', 80, Socket::Constants::AF_INET, Socket::SOCK_STREAM) { raise "Failed for test!" }

      assert_raise(RuntimeError.new("Failed for test!")) {
        @sd_dns.configure(parse_config(config))
      }
      assert_empty @sd_dns.services
    end

    test 'getaddrinfo raises an error with ignore_dns_error true' do
      stub(Socket).getaddrinfo('localhost', 80, Socket::Constants::AF_INET, Socket::SOCK_STREAM) { raise "Failed for test!" }

      assert_nothing_raised {
        @sd_dns.configure(parse_config(%[
          @type dns
          ignore_dns_error true
          <entry>
            host localhost
            port 80
            address_family ipv4
          </entry>
        ]))
      }
      assert_empty @sd_dns.services
      assert { @sd_dns.log.out.logs.any? { |log| log.include?('failed to get service list from localhost') }}
    end
  end

  sub_test_case '#start' do
    module TestTimerEventHelperWrapper
      # easy to control statsevent
      def timer_execute(_name, _interval, &block)
        @test_timer_event_helper_wrapper_context = Fiber.new do
          loop do
            block.call

            if Fiber.yield == :finish
              break
            end
          end
        end

        resume
      end

      def resume
        @test_timer_event_helper_wrapper_context.resume(:resume)
      end

      def shutdown
        super

        if @test_timer_event_helper_wrapper_context
          @test_timer_event_helper_wrapper_context.resume(:finish)
        end
      end
    end

    def config_with_interval
      %[
        @type dns
        interval 10s
        <entry>
          host localhost
          port 80
          address_family ipv4
        </entry>
      ]
    end

    teardown do
      if @sd_dns
        @sd_dns.stop unless @sd_dns.stopped?
        @sd_dns.before_shutdown unless @sd_dns.before_shutdown?
        @sd_dns.shutdown unless @sd_dns.shutdown?
        @sd_dns.after_shutdown unless @sd_dns.after_shutdown?
        @sd_dns.close unless @sd_dns.closed?
        @sd_dns.terminate unless @sd_dns.terminated?
      end
    end

    test 'Skip if service list are not updated' do
      @sd_dns.extend(TestTimerEventHelperWrapper)
      @sd_dns.configure(parse_config(config_with_interval))
      queue = []

      @sd_dns.start(queue)
      assert_empty queue

      @sd_dns.resume
      assert_empty queue
    end

    test 'if service list is changed, service_in and service_out event happen' do
      stub(Socket).getaddrinfo('localhost', 80, Socket::Constants::AF_INET, Socket::SOCK_STREAM) {
        [["AF_INET", 80, "localhost", "127.0.0.1", 2, 1, 6]]
      }
      @sd_dns.extend(TestTimerEventHelperWrapper)
      @sd_dns.configure(parse_config(config_with_interval))

      stub(Socket).getaddrinfo('localhost', 80, Socket::Constants::AF_INET, Socket::SOCK_STREAM) {
        [["AF_INET", 90, "localhost", "192.168.0.1", 2, 1, 6]]
      }
      queue = []
      @sd_dns.start(queue)

      join = queue.shift
      assert_equal Fluent::Plugin::ServiceDiscovery::SERVICE_IN, join.type
      assert_equal 90, join.service.port
      assert_equal '192.168.0.1', join.service.host

      drain = queue.shift
      assert_equal Fluent::Plugin::ServiceDiscovery::SERVICE_OUT, drain.type
      assert_equal 80, drain.service.port
      assert_equal '127.0.0.1', drain.service.host
    end
  end
end
