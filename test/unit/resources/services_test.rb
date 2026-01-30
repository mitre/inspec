# frozen_string_literal: true

require 'helper'
require 'inspec/resource'
require 'inspec/resources/services'

describe 'Inspec::Resources::Services' do
  # Sample service data for testing
  def sample_systemd_services
    [
      {
        name: 'sshd',
        description: 'OpenSSH server daemon',
        type: 'systemd',
        enabled: true,
        running: true,
        installed: true,
        startmode: nil,
        startname: nil
      },
      {
        name: 'dbus',
        description: 'D-Bus System Message Bus',
        type: 'systemd',
        enabled: true,
        running: true,
        installed: true,
        startmode: nil,
        startname: 'root'
      },
      {
        name: 'apache2',
        description: 'Apache Web Server',
        type: 'systemd',
        enabled: false,
        running: false,
        installed: true,
        startmode: nil,
        startname: 'www-data'
      }
    ]
  end

  def sample_windows_services
    [
      {
        name: 'dhcp',
        description: 'DHCP Client',
        type: 'windows',
        enabled: true,
        running: true,
        installed: true,
        startmode: 'Auto',
        startname: 'LocalSystem'
      },
      {
        name: 'winmgmt',
        description: 'Windows Management Instrumentation',
        type: 'windows',
        enabled: true,
        running: true,
        installed: true,
        startmode: 'Auto',
        startname: 'LocalSystem'
      }
    ]
  end

  # ========== Basic Resource Tests ==========
  describe 'resource initialization' do
    it 'creates a services resource with to_s' do
      resource = MockLoader.new(:ubuntu).load_resource('services')
      _(resource.to_s).must_equal 'Services'
    end

    it 'skips resource on unsupported OS' do
      resource = MockLoader.new(:undefined).load_resource('services')
      _(resource.resource_skipped?).must_equal true
    end
  end

  # ========== FilterTable Tests with Mocked Data ==========
  describe 'FilterTable functionality' do
    let(:resource) do
      MockLoader.new(:ubuntu).load_resource('services')
    end

    it 'provides names accessor' do
      resource.stub :collect_services_data, sample_systemd_services do
        _(resource.names).must_equal %w[sshd dbus apache2]
      end
    end

    it 'provides descriptions accessor' do
      resource.stub :collect_services_data, sample_systemd_services do
        descriptions = resource.descriptions
        _(descriptions).must_include 'OpenSSH server daemon'
        _(descriptions).must_include 'Apache Web Server'
      end
    end

    it 'provides types accessor' do
      resource.stub :collect_services_data, sample_systemd_services do
        _(resource.types.uniq).must_equal ['systemd']
      end
    end

    it 'provides enabled accessor' do
      resource.stub :collect_services_data, sample_systemd_services do
        _(resource.enabled).must_equal [true, true, false]
      end
    end

    it 'provides running accessor' do
      resource.stub :collect_services_data, sample_systemd_services do
        _(resource.running).must_equal [true, true, false]
      end
    end

    it 'provides installed accessor' do
      resource.stub :collect_services_data, sample_systemd_services do
        _(resource.installed).must_equal [true, true, true]
      end
    end

    it 'filters services by name' do
      resource.stub :collect_services_data, sample_systemd_services do
        filtered = resource.where(name: 'sshd')
        _(filtered.entries.length).must_equal 1
        _(filtered.names).must_equal ['sshd']
      end
    end

    it 'filters enabled services' do
      resource.stub :collect_services_data, sample_systemd_services do
        filtered = resource.where { enabled == true }
        _(filtered.names).must_equal %w[sshd dbus]
      end
    end

    it 'filters running services' do
      resource.stub :collect_services_data, sample_systemd_services do
        filtered = resource.where { running == true }
        _(filtered.names).must_equal %w[sshd dbus]
      end
    end

    it 'filters by service type' do
      resource.stub :collect_services_data, sample_systemd_services do
        filtered = resource.where(type: 'systemd')
        _(filtered.types.uniq).must_equal ['systemd']
      end
    end

    it 'chains multiple where clauses' do
      resource.stub :collect_services_data, sample_systemd_services do
        filtered = resource.where { enabled == true }.where { running == true }
        _(filtered.names).must_equal %w[sshd dbus]
      end
    end

    it 'combines block and hash filtering' do
      resource.stub :collect_services_data, sample_systemd_services do
        filtered = resource.where(type: 'systemd').where { enabled == true }
        _(filtered.names).must_equal %w[sshd dbus]
      end
    end

    it 'provides exists? matcher' do
      resource.stub :collect_services_data, sample_systemd_services do
        _(resource.where(name: 'sshd').exists?).must_equal true
        _(resource.where(name: 'nonexistent').exists?).must_equal false
      end
    end

    it 'provides enabled? matcher' do
      resource.stub :collect_services_data, sample_systemd_services do
        _(resource.where(name: 'sshd').enabled?).must_equal true
        _(resource.where(name: 'apache2').enabled?).must_equal false
      end
    end

    it 'provides running? matcher' do
      resource.stub :collect_services_data, sample_systemd_services do
        _(resource.where(name: 'sshd').running?).must_equal true
        _(resource.where(name: 'apache2').running?).must_equal false
      end
    end

    it 'provides installed? matcher' do
      resource.stub :collect_services_data, sample_systemd_services do
        _(resource.where(name: 'sshd').installed?).must_equal true
      end
    end

    it 'returns correct count' do
      resource.stub :collect_services_data, sample_systemd_services do
        _(resource.count).must_equal 3
      end
    end

    it 'includes startname when present' do
      resource.stub :collect_services_data, sample_systemd_services do
        dbus_service = resource.where(name: 'dbus').entries.first
        _(dbus_service[:startname]).must_equal 'root'
      end
    end

    it 'handles nil startname' do
      resource.stub :collect_services_data, sample_systemd_services do
        sshd_service = resource.where(name: 'sshd').entries.first
        _(sshd_service[:startname]).must_be_nil
      end
    end

    it 'handles empty filter results' do
      resource.stub :collect_services_data, sample_systemd_services do
        filtered = resource.where(name: 'nonexistent')
        _(filtered.entries).must_equal []
        _(filtered.exists?).must_equal false
      end
    end
  end

  # ========== Windows Services Tests ==========
  describe 'Windows services' do
    let(:resource) do
      MockLoader.new(:windows).load_resource('services')
    end

    it 'provides startmodes accessor' do
      resource.stub :collect_services_data, sample_windows_services do
        _(resource.startmodes).must_equal %w[Auto Auto]
      end
    end

    it 'provides startnames accessor' do
      resource.stub :collect_services_data, sample_windows_services do
        _(resource.startnames).must_equal %w[LocalSystem LocalSystem]
      end
    end

    it 'filters Windows services by type' do
      resource.stub :collect_services_data, sample_windows_services do
        filtered = resource.where(type: 'windows')
        _(filtered.types.uniq).must_equal ['windows']
      end
    end

    it 'includes startmode for Windows services' do
      resource.stub :collect_services_data, sample_windows_services do
        dhcp_service = resource.where(name: 'dhcp').entries.first
        _(dhcp_service[:startmode]).must_equal 'Auto'
      end
    end

    it 'includes startname for Windows services' do
      resource.stub :collect_services_data, sample_windows_services do
        dhcp_service = resource.where(name: 'dhcp').entries.first
        _(dhcp_service[:startname]).must_equal 'LocalSystem'
      end
    end
  end

  # ========== Edge Cases ==========
  describe 'edge cases' do
    let(:resource) do
      MockLoader.new(:ubuntu).load_resource('services')
    end

    it 'handles empty service list' do
      resource.stub :collect_services_data, [] do
        _(resource.entries).must_equal []
        _(resource.count).must_equal 0
        _(resource.exists?).must_equal false
      end
    end

    it 'handles services with nil descriptions' do
      services_with_nil = [
        {
          name: 'test',
          description: nil,
          type: 'sysv',
          enabled: true,
          running: false,
          installed: true,
          startmode: nil,
          startname: nil
        }
      ]
      resource.stub :collect_services_data, services_with_nil do
        _(resource.descriptions).must_equal [nil]
      end
    end

    it 'handles mixed enabled states' do
      resource.stub :collect_services_data, sample_systemd_services do
        enabled_count = resource.where { enabled == true }.count
        disabled_count = resource.where { enabled == false }.count
        _(enabled_count).must_equal 2
        _(disabled_count).must_equal 1
      end
    end
  end
end
