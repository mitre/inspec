require 'helper'
require 'inspec/resource'
require 'inspec/resources/sudoers'

describe 'Inspec::Resources::Sudoers' do
  describe 'properties and interface' do
    resource = load_resource('sudoers')

    it 'verifies resource_id is /etc/sudoers by default' do
      _(resource.resource_id).must_equal '/etc/sudoers'
    end

    it 'verifies raw_content is loaded' do
      _(resource.raw_content).wont_be_nil
      _(resource.raw_content).must_include 'Defaults'
    end
  end

  describe 'Default settings parsing' do
    let(:resource) { load_resource('sudoers') }

    it 'parses authentication flags correctly' do
      settings = resource.settings.Defaults
      _(settings).must_include '!authenticate'
      _(settings).must_include '!targetpw'
      _(settings).must_include '!rootpw'
      _(settings).must_include '!runaspw'
    end

    it 'parses timeout settings correctly' do
      timeout = resource.settings.Defaults['timestamp_timeout']
      _(timeout).wont_be_nil
      _(timeout.first.to_i).must_equal 0
    end

    it 'properly parses all user aliases' do
      user_aliases = resource.settings.User_Alias
      _(user_aliases).must_be_kind_of Hash
      _(user_aliases['ADMINS']).must_include 'admin'
      _(user_aliases['ADMINS']).must_include 'wheel'
    end

    it 'properly parses all command aliases' do
      cmd_aliases = resource.settings.Cmnd_Alias
      _(cmd_aliases).must_be_kind_of Hash
      _(cmd_aliases['SOFTWARE']).must_include '/bin/rpm'
      _(cmd_aliases['SERVICES']).must_include '/usr/sbin/service'
    end

    it 'handles multiple Defaults lines' do
      defaults = resource.settings.Defaults
      _(defaults.keys).must_include 'env_reset'
      _(defaults.keys).must_include 'mail_badpass'
    end

    it 'handles user-specific Defaults' do
      defaults = resource.settings['Defaults:root']
      _(defaults).wont_be_nil if defaults
    end

    it 'handles Defaults with multiple values' do
      env_keep = resource.settings.Defaults['env_keep']
      _(env_keep).must_be_kind_of Array
      _(env_keep).must_include 'HOME'
    end
  end

  describe 'Alias parsing' do
    let(:resource) { load_resource('sudoers') }

    it 'handles command alias expansion' do
      cmnd = resource.settings.Cmnd_Alias['SERVICES']
      _(cmnd).must_include '/usr/sbin/service'
      _(cmnd).must_include '/usr/bin/systemctl'
    end

    it 'handles user alias expansion' do
      users = resource.settings.User_Alias['ADMINS']
      _(users).must_include 'admin'
      _(users).must_include 'wheel'
    end

    it 'handles host alias expansion' do
      hosts = resource.settings.Host_Alias['WEBSERVERS']
      _(hosts).must_include 'www1'
      _(hosts).must_include 'www2'
    end
  end

  describe 'User specifications parsing' do
    resource = load_resource('sudoers')

    it 'parses user rules correctly' do
      user_rules = resource.rules.where { users == 'root' }
      _(user_rules.entries).wont_be_empty
      _(user_rules.entries.first[:hosts]).must_equal 'ALL'
      _(user_rules.entries.first[:commands]).must_equal 'ALL'
    end

    it 'parses host specifications correctly' do
      host_rules = resource.rules.where { hosts == 'WEBSERVERS' }
      _(host_rules.entries).wont_be_empty
      _(host_rules.entries.first[:users]).must_equal 'www-data'
      _(host_rules.entries.first[:commands]).must_equal '/usr/sbin/nginx'
    end

    it 'handles NOPASSWD tags' do
      nopasswd_rules = resource.rules.where { !tags.nil? && tags.include?('NOPASSWD:') }
      _(nopasswd_rules.entries).wont_be_empty
      _(nopasswd_rules.entries.first[:users]).must_equal 'admin'
    end

    it 'correctly parses run_as specifications' do
      run_as_rules = resource.rules.where { !run_as.nil? }
      _(run_as_rules.entries).wont_be_empty
      _(run_as_rules.entries.first[:run_as]).must_include 'ALL'
    end
  end

  describe 'Multiple file handling' do
    resource = load_resource('sudoers', ['/etc/sudoers', '/etc/sudoers.d/*'])

    it 'loads content from multiple files' do
      _(resource.raw_content).wont_be_empty
      _(resource.sudoers_files.count).must_equal 2
    end
  end

  describe 'Platform-specific handling' do
    it 'supports macOS (Darwin)' do
      resource = load_resource('sudoers', '/private/etc/sudoers')
      _(resource.resource_id).must_equal '/private/etc/sudoers'
      _(resource.raw_content).wont_be_nil
    end

    it 'supports FreeBSD' do
      resource = load_resource('sudoers', '/usr/local/etc/sudoers')
      _(resource.resource_id).must_equal '/usr/local/etc/sudoers'
      _(resource.raw_content).wont_be_nil
    end

    it 'supports Solaris' do
      resource = load_resource('sudoers', '/etc/opt/sudoers')
      _(resource.resource_id).must_equal '/etc/opt/sudoers'
      _(resource.raw_content).wont_be_nil
    end

    it 'supports AIX' do
      resource = load_resource('sudoers', '/etc/security/sudoers')
      _(resource.resource_id).must_equal '/etc/security/sudoers'
      _(resource.raw_content).wont_be_nil
    end
  end

  describe 'Helper methods' do
    let(:resource) { load_resource('sudoers') }

    it 'checks if authentication is required' do
      _(resource.authenticate?).must_equal true
    end

    it 'returns the timeout value' do
      _(resource.timeout_value).must_equal 0
    end

    it 'checks if a timeout value is set' do
      _(resource.timeout_value?).must_equal true
    end

    it 'returns user aliases' do
      user_aliases = resource.user_aliases
      _(user_aliases.entries).wont_be_empty if user_aliases
    end

    it 'returns command aliases' do
      command_aliases = resource.command_aliases
      _(command_aliases.entries).wont_be_empty if command_aliases
    end

    it 'returns default settings' do
      defaults = resource.defaults
      _(defaults.entries).wont_be_empty if defaults
    end

    it 'returns user-specific defaults' do
      user_defaults = resource.user_defaults('root')
      _(user_defaults.entries).wont_be_empty if user_defaults
    end
  end
end
