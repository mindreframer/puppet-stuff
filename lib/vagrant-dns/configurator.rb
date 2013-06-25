require 'fileutils'
require 'yaml'

module VagrantDNS
  class Configurator
    attr_accessor :vm, :tmp_path

    def initialize(vm, tmp_path)
      @vm = vm
      @tmp_path = tmp_path
    end

    def run!
      regenerate_resolvers!
      ensure_deamon_env!
      register_patterns!
    end

    private
      def regenerate_resolvers!
        FileUtils.mkdir_p(resolver_folder)

        port = VagrantDNS::Config.listen.first.last
        tlds = dns_options(vm)[:tlds]

        tlds.each do |tld|
          File.open(File.join(resolver_folder, tld), "w") do |f|
            f << resolver_file(port)
          end
        end
      end

      def register_patterns!
        registry = YAML.load(File.read(config_file)) if File.exists?(config_file)
        registry ||= {}
        opts     = dns_options(vm)
        patterns = opts[:patterns] || default_patterns(opts)
        networks = opts[:networks]
        network = {}
        networks.each do |nw|
          network = nw if nw.first == :private_network
        end

        if network
          ip     = network.last[:ip]
        else
          ip     = '127.0.0.1'
        end

        patterns.each do |p|
          p = p.source if p.respond_to? :source # Regexp#to_s is unusable
          registry[p] = ip
        end

        File.open(config_file, "w") { |f| f << YAML.dump(registry) }
      end

      def dns_options(vm)
        dns_options = vm.config.dns.to_hash
        dns_options[:host_name] = vm.config.vm.hostname
        dns_options[:networks] = vm.config.vm.networks
        dns_options
      end

      def default_patterns(opts)
        if opts[:host_name]
          opts[:tlds].map { |tld| /^.*#{opts[:host_name]}.#{tld}$/ }
        else
          warn 'TLD but no host_name given. No patterns will be configured.'
          []
        end
      end

      def resolver_file(port)
        contents = <<-FILE
# this file is generated by vagrant-dns
nameserver 127.0.0.1
port #{port}
FILE
      end

      def resolver_folder
        File.join(tmp_path, "resolver")
      end

      def ensure_deamon_env!
        FileUtils.mkdir_p(File.join(tmp_path, "daemon"))
      end

      def config_file
        File.join(tmp_path, "config")
      end
  end
end
