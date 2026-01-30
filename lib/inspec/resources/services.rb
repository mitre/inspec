# frozen_string_literal: true

require 'inspec/resources/service'
require 'inspec/utils/filter'

module Inspec
  module Resources
    # The Services resource lists all services on a system and allows filtering
    # by various properties (name, type, enabled status, running status, etc.)
    #
    # Usage:
    #   describe services do
    #     its('names') { should include 'sshd' }
    #   end
    #
    #   describe services.where(name: 'sshd') do
    #     it { should be_enabled }
    #     it { should be_running }
    #   end
    class Services < Inspec.resource(1)
      name 'services'
      supports platform: 'unix'
      supports platform: 'windows'
      desc 'Use the services InSpec audit resource to list all services on the system and filter them by properties'
      example <<~EXAMPLE
        # List all service names
        describe services do
          its('names') { should include 'sshd' }
        end

        # Filter running services
        describe services.where { running == true } do
          its('names') { should include 'sshd' }
        end

        # Filter by service type
        describe services.where(type: 'systemd') do
          it { should exist }
        end

        # Find enabled services
        describe services.where(enabled: true) do
          its('count') { should be >= 5 }
        end
      EXAMPLE

      def initialize
        @service_mgmt = select_service_mgmt
        return skip_resource 'The `services` resource is not supported on your OS yet.' if @service_mgmt.nil?
      end

      # Setup FilterTable with columns for service properties
      filter = FilterTable.create
      filter.register_custom_matcher(:exists?) { |filter_table| !filter_table.entries.empty? }
      filter.register_column(:names, field: :name)
            .register_column(:descriptions, field: :description)
            .register_column(:types, field: :type)
            .register_column(:enabled, field: :enabled)
            .register_column(:running, field: :running)
            .register_column(:installed, field: :installed)
            .register_column(:startmodes, field: :startmode)
            .register_column(:startnames, field: :startname)
      filter.register_custom_matcher(:enabled?) { |filter_table| filter_table.where { enabled == true }.entries.any? }
      filter.register_custom_matcher(:running?) { |filter_table| filter_table.where { running == true }.entries.any? }
      filter.register_custom_matcher(:installed?) do |filter_table|
        filter_table.where do
          installed == true
        end.entries.any?
      end
      filter.install_filter_methods_on_resource(self, :collect_services_data)

      def to_s
        'Services'
      end

      private

      # Select the appropriate service manager based on the operating system
      def select_service_mgmt # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
        os = inspec.os
        platform = os[:name]

        return WindowsServiceManager.new(inspec) if os.windows?

        case platform
        when 'ubuntu'
          version = os[:release].to_f
          if version < 15.04
            UpstartServiceManager.new(inspec)
          else
            SystemdServiceManager.new(inspec)
          end
        when 'linuxmint'
          version = os[:release].to_f
          if version < 18
            UpstartServiceManager.new(inspec)
          else
            SystemdServiceManager.new(inspec)
          end
        when 'debian'
          version = if os[:release] == 'buster/sid'
                      10
                    else
                      os[:release].to_i
                    end
          if version > 7
            SystemdServiceManager.new(inspec)
          elsif version.positive?
            SysVServiceManager.new(inspec)
          end
        when 'redhat', 'fedora', 'centos', 'oracle', 'cloudlinux', 'scientific', 'rocky', 'almalinux'
          version = os[:release].to_i

          systemd = ((platform != 'fedora' && version >= 7) ||
                     (platform == 'fedora' && version >= 15))

          if systemd
            SystemdServiceManager.new(inspec)
          else
            SysVServiceManager.new(inspec)
          end
        when 'alibaba'
          if os[:release].to_i >= 3
            SystemdServiceManager.new(inspec)
          else
            SysVServiceManager.new(inspec)
          end
        when 'wrlinux'
          SysVServiceManager.new(inspec)
        when 'mac_os_x', 'darwin'
          LaunchCtlServiceManager.new(inspec)
        when 'freebsd'
          version = os[:release].to_f
          if version < 10
            BSDServiceManager.new(inspec)
          else
            FreeBSD10ServiceManager.new(inspec)
          end
        when 'arch'
          SystemdServiceManager.new(inspec)
        when 'coreos'
          SystemdServiceManager.new(inspec)
        when 'suse', 'opensuse'
          if os[:release].to_i >= 12
            SystemdServiceManager.new(inspec)
          else
            SysVServiceManager.new(inspec)
          end
        when 'aix'
          SrcMstrServiceManager.new(inspec)
        when 'amazon'
          # If `initctl` exists on the system, use `Upstart`. Else use `Systemd`
          if inspec.command('initctl').exist? || inspec.command('/sbin/initctl').exist?
            UpstartServiceManager.new(inspec)
          else
            SystemdServiceManager.new(inspec)
          end
        when 'solaris', 'smartos', 'omnios', 'openindiana', 'opensolaris', 'nexentacore'
          SvcsServiceManager.new(inspec)
        when 'yocto'
          SystemdServiceManager.new(inspec)
        when 'alpine'
          SysVServiceManager.new(inspec)
        end
      end

      # Collect all service data from the service manager
      def collect_services_data
        return [] if @service_mgmt.nil?

        @services_cache ||= @service_mgmt.list_all_services
      end
    end

    # Base class for service managers that provide list_all_services method
    class BaseServiceManager
      attr_reader :inspec

      def initialize(inspec)
        @inspec = inspec
      end

      # Must be implemented by subclasses
      def list_all_services
        raise NotImplementedError, 'Subclass must implement list_all_services method'
      end
    end

    # Systemd-based service manager
    class SystemdServiceManager < BaseServiceManager
      def list_all_services
        cmd = inspec.command('systemctl list-unit-files --type=service --all --no-pager')
        return [] if cmd.exit_status != 0

        # Collect all service names and their unit file states
        service_info = []
        cmd.stdout.split("\n").each do |line|
          # Skip header and footer lines
          next if line =~ /^UNIT FILE/ || line =~ /^\s*$/ || line =~ /unit files listed/

          # Parse format: servicename.service state
          parts = line.split
          next if parts.length < 2

          service_name = parts[0].gsub(/\.service$/, '')
          unit_file_state = parts[1]

          service_info << { name: service_name, unit_name: parts[0], state: unit_file_state }
        end

        return [] if service_info.empty?

        # Get detailed info for ALL services in one command
        all_unit_names = service_info.map { |s| s[:unit_name] }.join(' ')
        info_cmd = inspec.command("systemctl show --no-pager --all #{all_unit_names}")
        return [] if info_cmd.exit_status != 0

        # Parse the combined output - systemctl show outputs each service separated by blank lines
        service_blocks = info_cmd.stdout.split("\n\n")
        services = []

        service_blocks.each_with_index do |block, idx|
          next if block.strip.empty?
          break if idx >= service_info.length

          # Parse systemctl show output for this service
          params = SimpleConfig.new(
            block.chomp,
            assignment_regex: /^\s*([^=]*?)\s*=\s*(.*?)\s*$/,
            multiple_values: false
          ).params

          service_data = service_info[idx]

          # Check if running
          active_state = params['ActiveState']
          running = active_state == 'active'

          # Check if enabled
          enabled = %w[enabled static indirect generated].include?(service_data[:state])

          # Get startname (User field)
          startname = params['User']

          services << {
            name: service_data[:name],
            description: params['Description'],
            installed: params['LoadState'] == 'loaded',
            running:,
            enabled:,
            type: 'systemd',
            startmode: nil,
            startname:
          }
        end

        services
      end
    end

    # SysV-based service manager
    class SysVServiceManager < BaseServiceManager
      def list_all_services
        # Get list of services from /etc/init.d/
        cmd = inspec.command('ls -1 /etc/init.d/')
        return [] if cmd.exit_status != 0

        services = []
        cmd.stdout.split("\n").each do |service_name|
          next if service_name.empty? || service_name == 'README'

          # Check if enabled (look for symlinks in rc*.d directories)
          enabled_cmd = inspec.command('find /etc/rc*.d /etc/init.d/rc*.d -name "S*" 2>/dev/null')
          service_pattern = %r{rc[0-6]\.d/S[^/]*?#{Regexp.escape(service_name)}$}
          enabled = !enabled_cmd.stdout.scan(service_pattern).empty?

          # Check if running
          status_cmd = inspec.command("service #{service_name} status")
          running = status_cmd.exit_status.zero?

          services << {
            name: service_name,
            description: nil,
            installed: true,
            running:,
            enabled:,
            type: 'sysv',
            startmode: nil,
            startname: nil
          }
        end

        services
      end
    end

    # Upstart-based service manager
    class UpstartServiceManager < BaseServiceManager
      def list_all_services
        cmd = inspec.command('initctl list')
        return [] if cmd.exit_status != 0

        services = []
        cmd.stdout.split("\n").each do |line|
          # Parse format: servicename start/running, process 1234
          # or: servicename stop/waiting
          parts = line.split
          next if parts.empty?

          service_name = parts[0]
          status_info = parts[1] if parts.length > 1

          running = status_info =~ %r{start/running} ? true : false

          # Check if enabled by reading config file
          config_cmd = inspec.command("cat /etc/init/#{service_name}.conf 2>/dev/null")
          enabled = false
          enabled = !config_cmd.stdout.match(/^\s*start on/).nil? if config_cmd.exit_status.zero?

          services << {
            name: service_name,
            description: nil,
            installed: true,
            running:,
            enabled:,
            type: 'upstart',
            startmode: nil,
            startname: nil
          }
        end

        services
      end
    end

    # Windows service manager
    class WindowsServiceManager < BaseServiceManager
      def list_all_services
        # Use PowerShell to get all services
        script = <<~EOH
          Get-Service | Select-Object -Property Name, DisplayName, Status | ConvertTo-Json
        EOH
        cmd = inspec.powershell(script)

        begin
          services_data = JSON.parse(cmd.stdout)
        rescue JSON::ParserError
          return []
        end

        # Ensure we have an array
        services_data = [services_data] unless services_data.is_a?(Array)

        services = []
        services_data.each do |svc|
          # Get WMI data for more details
          wmi_script = <<~EOH
            Get-WmiObject -Class Win32_Service | Where-Object {$_.Name -eq '#{svc['Name']}'} | Select-Object -Property StartMode, StartName | ConvertTo-Json
          EOH
          wmi_cmd = inspec.powershell(wmi_script)

          startmode = nil
          startname = nil
          begin
            wmi_data = JSON.parse(wmi_cmd.stdout)
            startmode = wmi_data['StartMode'] unless wmi_data.nil?
            startname = wmi_data['StartName'] unless wmi_data.nil?
          rescue JSON::ParserError
            # Continue without WMI data
          end

          # Status mapping: Stopped=1, Starting=2, Stopping=3, Running=4, etc.
          running = svc['Status'] == 4

          # Enabled if StartMode is Auto or Manual
          enabled = %w[Auto Manual].include?(startmode)

          services << {
            name: svc['Name'],
            description: svc['DisplayName'],
            installed: true,
            running:,
            enabled:,
            type: 'windows',
            startmode:,
            startname:
          }
        end

        services
      end
    end

    # macOS/Darwin LaunchCtl service manager
    class LaunchCtlServiceManager < BaseServiceManager
      def list_all_services
        cmd = inspec.command('launchctl list')
        return [] if cmd.exit_status != 0

        services = []
        cmd.stdout.split("\n").each do |line|
          # Skip header line
          next if line =~ /^PID\s+Status\s+Label/

          # Parse format: PID Status Label
          parts = line.split(/\s+/, 3)
          next if parts.length < 3

          pid = parts[0]
          label = parts[2]

          # Extract service name from label
          service_name = label.split('.').last || label

          running = pid != '-'
          enabled = true # If it's in the list, it's enabled

          services << {
            name: service_name,
            description: nil,
            installed: true,
            running:,
            enabled:,
            type: 'darwin',
            startmode: nil,
            startname: nil
          }
        end

        services
      end
    end

    # BSD service manager (FreeBSD < 10)
    class BSDServiceManager < BaseServiceManager
      def list_all_services
        cmd = inspec.command('service -e')
        return [] if cmd.exit_status != 0

        services = []
        cmd.stdout.split("\n").each do |line|
          # Format: /etc/rc.d/servicename
          match = %r{^.*/(.*?)$}.match(line)
          next if match.nil?

          service_name = match[1]

          # Check if running
          status_cmd = inspec.command("service #{service_name} onestatus")
          running = status_cmd.exit_status.zero?

          services << {
            name: service_name,
            description: nil,
            installed: true,
            running:,
            enabled: true, # Listed by service -e means enabled
            type: 'bsd-init',
            startmode: nil,
            startname: nil
          }
        end

        services
      end
    end

    # FreeBSD 10+ service manager
    class FreeBSD10ServiceManager < BaseServiceManager
      def list_all_services
        # List all available services
        cmd = inspec.command('service -l')
        return [] if cmd.exit_status != 0

        services = []
        cmd.stdout.split("\n").each do |service_name|
          next if service_name.strip.empty?

          # Check if enabled
          enabled_cmd = inspec.command("service #{service_name} enabled")
          enabled = enabled_cmd.exit_status.zero?

          # Check if running
          status_cmd = inspec.command("service #{service_name} onestatus")
          running = status_cmd.exit_status.zero?

          services << {
            name: service_name,
            description: nil,
            installed: true,
            running:,
            enabled:,
            type: 'bsd-init',
            startmode: nil,
            startname: nil
          }
        end

        services
      end
    end

    # AIX service manager
    class SrcMstrServiceManager < BaseServiceManager
      def list_all_services
        cmd = inspec.command('lssrc -a')
        return [] if cmd.exit_status != 0

        services = []
        cmd.stdout.split("\n").each do |line|
          # Skip header
          next if line =~ /^Subsystem/

          parts = line.split
          next if parts.length < 3

          service_name = parts[0]
          status = parts[2]

          running = status == 'active'

          # Check if enabled (in /etc/rc.tcpip or /etc/inittab)
          enabled_rc = inspec.command("grep -v ^# /etc/rc.tcpip | grep 'start ' | grep -Eq '(/{0,1}| )#{service_name} '").exit_status.zero?
          enabled_inittab = inspec.command("lsitab #{service_name}").exit_status.zero?
          enabled = enabled_rc || enabled_inittab

          services << {
            name: service_name,
            description: nil,
            installed: true,
            running:,
            enabled:,
            type: 'srcmstr',
            startmode: nil,
            startname: nil
          }
        end

        services
      end
    end

    # Solaris service manager
    class SvcsServiceManager < BaseServiceManager
      def list_all_services
        cmd = inspec.command('svcs -a')
        return [] if cmd.exit_status != 0

        services = []
        cmd.stdout.split("\n").each do |line|
          # Skip header
          next if line =~ /^STATE/

          parts = line.split
          next if parts.length < 3

          state = parts[0]
          service_name = parts[2]

          running = state == 'online'
          enabled = state != 'disabled'

          services << {
            name: service_name,
            description: nil,
            installed: true,
            running:,
            enabled:,
            type: 'svcs',
            startmode: nil,
            startname: nil
          }
        end

        services
      end
    end
  end
end
