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
      require 'pry'
      binding.pry
    end
  end

  # describe 'Default settings parsing' do
  #   let(:resource) { load_resource('sudoers') }

  #   it 'parses authentication flags correctly' do
  #     settings = resource.settings.where(name: '!authenticate').entries
  #     _(settings).wont_be_empty
  #     settings.each do |detail|
  #       _(detail[:binding_type]).must_equal 'negated_command'
  #       _(detail[:binding_target]).must_equal '!authenticate'
  #       _(detail[:value]).must_equal ''
  #     end
  #   end

  #   it 'parses timeout settings correctly' do
  #     timeout = resource.settings.where(name: 'timestamp_timeout').values.flatten.first
  #     _(timeout).wont_be_nil
  #     _(timeout).must_equal '0'
  #   end

  #   it 'properly parses all user aliases' do
  #     user_aliases = resource.user_aliases.entries
  #     _(user_aliases).must_be_kind_of Array
  #     _(user_aliases.map(&:name)).must_include 'ADMINS'
  #     _(user_aliases.map(&:name)).must_include 'DBAS'
  #     _(user_aliases.map(&:name)).must_include 'WEBMASTERS'
  #   end

  #   it 'properly parses all command aliases' do
  #     cmd_aliases = resource.command_aliases.entries
  #     _(cmd_aliases).must_be_kind_of Array
  #     _(cmd_aliases.map(&:name)).must_include 'SOFTWARE'
  #     _(cmd_aliases.map(&:name)).must_include 'SERVICES'
  #     _(cmd_aliases.map(&:name)).must_include 'STORAGE'
  #   end

  #   it 'handles multiple Defaults lines' do
  #     defaults = resource.defaults.entries
  #     _(defaults).wont_be_empty
  #     _(defaults.map(&:name)).must_include 'env_reset'
  #     _(defaults.map(&:name)).must_include 'mail_badpass'
  #   end

  #   it 'handles user-specific Defaults' do
  #     require 'pry'
  #     binding.pry
  #     defaults = resource.user_defaults('root').entries
  #     _(defaults).wont_be_nil if defaults
  #     _(defaults.map(&:setting)).must_include 'umask'
  #     _(defaults.map(&:value)).must_include '027'
  #   end

  #   it 'handles Defaults with multiple values' do
  #     env_keep = resource.settings.where(name: 'env_keep').values.flatten
  #     _(env_keep).must_be_kind_of Array
  #     _(env_keep).must_include 'HOME'
  #     _(env_keep).must_include 'MAIL'
  #   end

  #   it 'handles user-specific Defaults' do
  #     root_defaults = resource.user_defaults('root').entries
  #     _(root_defaults).wont_be_nil
  #     _(root_defaults.first[:value]).must_equal '027'
  #   end

  #   it 'handles multiple user-specific Defaults' do
  #     custom_user_defaults = resource.user_defaults('custom_user').entries
  #     _(custom_user_defaults).wont_be_nil
  #     _(custom_user_defaults.first[:value]).must_equal '1'
  #   end

  #   it 'handles user-specific Defaults through helper method' do
  #     root_settings = resource.user_defaults('root').entries
  #     _(root_settings).wont_be_nil
  #     _(root_settings.first[:value]).must_equal '027'

  #     operator_settings = resource.user_defaults('operator').entries
  #     _(operator_settings).wont_be_nil

  #     custom_settings = resource.user_defaults('custom_user').entries
  #     _(custom_settings.first[:value]).must_equal '1'
  #   end

  #   it 'handles user-specific Defaults' do
  #     settings = resource.settings.where(name: 'umask=027').entries
  #     _(settings).wont_be_empty
  #     _(settings.first[:value]).must_include 'umask=027'
  #   end

  #   it 'handles multiple user-specific Defaults' do
  #     settings = resource.settings.where(name: 'ignore_dot=1').entries
  #     _(settings).wont_be_empty
  #     _(settings.first[:value]).must_include 'ignore_dot=1'
  #   end

  #   it 'handles user-specific Defaults through helper method' do
  #     root_settings = resource.user_defaults('root').entries
  #     _(root_settings).wont_be_empty
  #     _(root_settings.first[:value]).must_include 'umask=027'

  #     operator_settings = resource.user_defaults('operator').entries
  #     _(operator_settings).wont_be_empty
  #     _(operator_settings.first[:value]).must_include 'log_output'
  #   end

  #   it 'handles multiple settings within a single user-specific Defaults' do
  #     settings = resource.settings.where(name: 'Defaults:www-data').entries
  #     _(settings).wont_be_empty
  #     settings.each do |detail|
  #       _(detail[:binding_type]).wont_be_nil
  #       _(detail[:binding_target]).wont_be_nil
  #       case detail[:setting]
  #       when '!authenticate'
  #         _(detail[:value]).must_include '022'
  #       when 'umask'
  #         _(detail[:value]).must_equal '022'
  #       end
  #     end
  #   end

  #   it 'handles multiple settings within a single targeted Default entry' do
  #     settings = resource.settings.where(name: 'Defaults:developer').entries
  #     _(settings).wont_be_empty
  #     settings.each do |detail|
  #       _(detail[:binding_type]).wont_be_nil
  #       _(detail[:binding_target]).wont_be_nil
  #       case detail[:setting]
  #       when 'env_reset'
  #         _(detail[:value]).must_include 'env_reset'
  #       when 'secure_path'
  #         _(detail[:value]).must_include '/usr/local/bin:/usr/bin'
  #       when 'umask'
  #         _(detail[:value]).must_equal '022'
  #       end
  #     end
  #   end
  # end

  # describe 'Alias parsing' do
  #   let(:resource) { load_resource('sudoers') }

  #   it 'handles command alias expansion' do
  #     cmnd = resource.settings.Cmnd_Alias['SERVICES']
  #     _(cmnd).must_include '/usr/sbin/service'
  #     _(cmnd).must_include '/usr/bin/systemctl'
  #   end

  #   it 'handles user alias expansion' do
  #     users = resource.settings.User_Alias['ADMINS']
  #     _(users).must_include 'admin'
  #     _(users).must_include 'wheel'
  #   end

  #   it 'handles host alias expansion' do
  #     hosts = resource.settings.Host_Alias['WEBSERVERS']
  #     _(hosts).must_include 'www1'
  #     _(hosts).must_include 'www2'
  #   end
  # end

  # describe 'User specifications parsing' do
  #   resource = load_resource('sudoers')

  #   it 'parses user rules correctly' do
  #     user_rules = resource.rules.where { users == 'root' }
  #     _(user_rules.entries).wont_be_empty
  #     _(user_rules.entries.first[:hosts]).must_equal 'ALL'
  #     _(user_rules.entries.first[:commands]).must_be_kind_of(String)
  #     _(user_rules.entries.first[:commands]).must_equal 'ALL'
  #   end

  #   it 'parses host specifications correctly' do
  #     host_rules = resource.rules.where { hosts == 'WEBSERVERS' }
  #     _(host_rules.entries).wont_be_empty
  #     _(host_rules.entries.first[:users]).must_equal 'www-data'
  #     _(host_rules.entries.first[:commands]).must_equal '/usr/sbin/nginx'
  #   end

  #   it 'handles NOPASSWD tags' do
  #     nopasswd_rules = resource.rules.where { !tags.nil? && tags.include?('NOPASSWD:') }
  #     _(nopasswd_rules.entries).wont_be_empty
  #     _(nopasswd_rules.entries.first[:users]).must_equal 'admin'
  #   end

  #   it 'correctly parses run_as specifications' do
  #     run_as_rules = resource.rules.where { !run_as.nil? }
  #     _(run_as_rules.entries).wont_be_empty
  #     _(run_as_rules.entries.first[:run_as]).must_include 'ALL'
  #   end
  # end

  # describe 'Multiple file handling' do
  #   resource = load_resource('sudoers', ['/etc/sudoers', '/etc/sudoers.d/*'])

  #   it 'loads content from multiple files' do
  #     _(resource.raw_content).wont_be_empty
  #     _(resource.sudoers_files.count).must_equal 2
  #   end
  # end

  # describe 'Platform-specific handling' do
  #   it 'supports macOS (Darwin)' do
  #     resource = load_resource('sudoers', '/private/etc/sudoers')
  #     _(resource.resource_id).must_equal '/private/etc/sudoers'
  #     _(resource.raw_content).wont_be_nil
  #   end

  #   it 'supports FreeBSD' do
  #     resource = load_resource('sudoers', '/usr/local/etc/sudoers')
  #     _(resource.resource_id).must_equal '/usr/local/etc/sudoers'
  #     _(resource.raw_content).wont_be_nil
  #   end

  #   it 'supports Solaris' do
  #     resource = load_resource('sudoers', '/etc/opt/sudoers')
  #     _(resource.resource_id).must_equal '/etc/opt/sudoers'
  #     _(resource.raw_content).wont_be_nil
  #   end

  #   it 'supports AIX' do
  #     resource = load_resource('sudoers', '/etc/security/sudoers')
  #     _(resource.resource_id).must_equal '/etc/security/sudoers'
  #     _(resource.raw_content).wont_be_nil
  #   end
  # end

  # describe 'Helper methods' do
  #   let(:resource) { load_resource('sudoers') }

  #   it 'checks if authentication is required' do
  #     _(resource.authenticate?).must_equal true
  #   end

  #   it 'returns the timeout value' do
  #     _(resource.timeout_value).must_equal 0
  #   end

  #   it 'checks if a timeout value is set' do
  #     _(resource.timeout_value?).must_equal true
  #   end

  #   it 'returns user aliases' do
  #     user_aliases = resource.user_aliases
  #     _(user_aliases.entries).wont_be_empty if user_aliases
  #   end

  #   it 'returns command aliases' do
  #     command_aliases = resource.command_aliases
  #     _(command_aliases.entries).wont_be_empty if command_aliases
  #   end

  #   it 'returns default settings' do
  #     defaults = resource.defaults
  #     _(defaults.entries).wont_be_empty if defaults
  #   end

  #   it 'returns user-specific defaults' do
  #     user_defaults = resource.user_defaults('root')
  #     _(user_defaults.entries).wont_be_empty if user_defaults
  #   end

  #   it 'returns user-specific defaults' do
  #     defaults = resource.user_defaults('root')
  #     _(defaults).wont_be_empty
  #     _(defaults.entries.first['value']).must_include 'umask=027'
  #   end
  # end

  # describe 'Basic Helper Methods' do
  #   let(:resource) { load_resource('sudoers') }

  #   it 'handles LOG_INPUT rules' do
  #     _(resource.loginput_rules.entries).wont_be_empty
  #   end

  #   it 'handles LOG_OUTPUT rules' do
  #     _(resource.logoutput_rules.entries).wont_be_empty
  #   end

  #   it 'handles NOEXEC rules' do
  #     _(resource.noexec_rules.entries).wont_be_empty
  #   end
  # end

  # describe 'Ignored directives' do
  #   it 'ignores specified directives' do
  #     resource = load_resource('sudoers', nil, ['#includedir', '#ignoreme'])
  #     _(resource.raw_content).wont_include '#ignoreme'
  #   end
  # end

  # describe 'Logging and execution control' do
  #   let(:resource) { load_resource('sudoers') }

  #   describe 'tag-based rules' do
  #     it 'identifies LOG_INPUT rules' do
  #       rules = resource.loginput_rules
  #       _(rules).wont_be_empty
  #       # Look specifically for auditor's rules
  #       auditor_rules = rules.where { users == 'auditor' }
  #       _(auditor_rules.entries).wont_be_empty
  #       _(auditor_rules.entries.first[:commands]).must_include '/usr/bin/cat'
  #     end

  #     it 'identifies LOG_OUTPUT rules' do
  #       rules = resource.logoutput_rules
  #       _(rules).wont_be_empty
  #       # Look specifically for auditor's rules
  #       auditor_rules = rules.where { users == 'auditor' }
  #       _(auditor_rules.entries).wont_be_empty
  #       _(auditor_rules.entries.first[:commands]).must_include '/usr/bin/less'
  #     end

  #     it 'identifies NOEXEC rules' do
  #       rules = resource.noexec_rules
  #       _(rules).wont_be_empty
  #       _(rules.entries.first[:users]).must_equal 'developer'
  #       _(rules.entries.first[:commands]).must_include '/usr/bin/vim'
  #     end
  #   end

  #   describe 'convenience methods' do
  #     it 'provides command lists' do
  #       _(resource.nopasswd_commands).must_include '/usr/bin/su'
  #       _(resource.noexec_commands).must_include '/usr/bin/vim'
  #       _(resource.logged_commands).must_include '/usr/bin/cat'
  #     end

  #     it 'provides user command mapping' do
  #       map = resource.user_command_map
  #       _(map['admin']).must_include '/usr/bin/su'
  #       _(map['developer']).must_include '/usr/bin/vim'
  #     end

  #     it 'provides tag summary' do
  #       summary = resource.tag_summary
  #       _(summary['NOPASSWD:']).must_equal 3  # admin (2) and dbadmin
  #       _(summary['NOEXEC:']).must_equal 3    # developer (2) and security
  #       _(summary['LOG_INPUT:']).must_equal 5 # admin, auditor, dbadmin, and security (2)
  #     end
  #   end
  # end

  # describe 'Enhanced helper methods' do
  #   let(:resource) { load_resource('sudoers') }

  #   describe 'commands summary methods' do
  #     it 'returns all commands that can be executed without password' do
  #       cmds = resource.nopasswd_commands
  #       _(cmds).must_include '/usr/bin/su'
  #       _(cmds).must_include '/usr/bin/sudo'
  #       _(cmds).must_include '/usr/bin/mysql'
  #     end

  #     it 'returns all commands that must be executed with NOEXEC' do
  #       cmds = resource.noexec_commands
  #       _(cmds).must_include '/usr/bin/vim'
  #       _(cmds).must_include '/usr/bin/nano'
  #       _(cmds).must_include '/usr/bin/tcpdump'
  #     end

  #     it 'returns all commands that are logged' do
  #       cmds = resource.logged_commands
  #       _(cmds).must_include '/usr/bin/cat'
  #       _(cmds).must_include '/usr/bin/less'
  #       _(cmds).must_include '/usr/bin/tcpdump'
  #     end
  #   end

  #   describe 'user command mapping' do
  #     it 'returns a hash of users and their allowed commands' do
  #       map = resource.user_command_map
  #       _(map['admin']).must_include '/usr/bin/su'
  #       _(map['developer']).must_include '/usr/bin/vim'
  #       _(map['auditor']).must_include '/usr/bin/cat'
  #     end
  #   end

  #   describe 'tag summary' do
  #     it 'returns count of each tag type' do
  #       summary = resource.tag_summary
  #       _(summary['NOPASSWD:']).must_equal 2  # admin and dbadmin
  #       _(summary['NOEXEC:']).must_equal 2    # developer and security
  #       _(summary['LOG_INPUT:']).must_equal 3 # auditor, dbadmin, and security
  #     end
  #   end

  #   describe 'rules with tag filtering' do
  #     it 'returns rules filtered by tag' do
  #       rules = resource.rules_with_tag('SETENV:')
  #       _(rules.entries.first[:users]).must_equal 'poweruser'
  #       _(rules.entries.first[:commands]).must_include '/usr/bin/docker'
  #     end
  #   end
  # end

  # describe 'Settings filter functionality' do
  #   let(:resource) { load_resource('sudoers') }

  #   describe 'user defaults' do
  #     it 'properly identifies user-specific defaults' do
  #       settings = resource.settings_filter.where(type: 'user_default', user: 'root')
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:setting]).must_equal 'umask'
  #       _(settings.entries.first[:value]).must_equal '027'
  #     end

  #     it 'handles multiple settings for the same user' do
  #       settings = resource.settings_filter.where(type: 'user_default', user: 'operator')
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:setting]).must_equal 'log_output'
  #     end

  #     it 'provides access through helper method' do
  #       settings = resource.user_defaults('root')
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:setting]).must_equal 'umask'
  #       _(settings.entries.first[:value]).must_equal '027'
  #     end
  #   end

  #   describe 'global defaults' do
  #     it 'properly identifies global defaults' do
  #       settings = resource.settings_filter.where(type: 'global_default')
  #       _(settings).wont_be_empty
  #       _(settings.entries.map { |e| e[:name] }).must_include 'env_reset'
  #       _(settings.entries.map { |e| e[:name] }).must_include 'mail_badpass'
  #     end

  #     it 'handles defaults with values' do
  #       setting = resource.settings_filter.where(type: 'global_default', name: 'timestamp_timeout')
  #       _(setting).wont_be_empty
  #       _(setting.entries.first[:value]).must_equal '0'
  #     end

  #     it 'provides access through helper method' do
  #       settings = resource.global_defaults
  #       _(settings).wont_be_empty
  #       _(settings.entries.map { |e| e[:name] }).must_include 'env_reset'
  #     end
  #   end

  #   describe 'alias entries' do
  #     it 'properly identifies alias entries' do
  #       settings = resource.settings_filter.where(type: 'alias')
  #       _(settings).wont_be_empty
  #     end

  #     it 'preserves alias categories' do
  #       settings = resource.settings_filter.where(type: 'alias', category: 'Host_Alias')
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:name]).must_equal 'SERVERS'
  #       _(settings.entries.first[:value]).must_equal 'server1,server2'
  #     end

  #     it 'provides access through helper method' do
  #       settings = resource.all_aliases
  #       _(settings).wont_be_empty
  #       categories = settings.entries.map { |e| e[:category] }.uniq
  #       _(categories).must_include 'Host_Alias'
  #       _(categories).must_include 'User_Alias'
  #       _(categories).must_include 'Cmnd_Alias'
  #     end
  #   end

  #   describe 'filter combinations' do
  #     it 'allows filtering by multiple criteria' do
  #       settings = resource.settings_filter.where(
  #         type: 'user_default',
  #         user: 'root',
  #         setting: 'umask'
  #       )
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:value]).must_equal '027'
  #     end

  #     it 'handles complex value queries' do
  #       settings = resource.settings_filter.where(type: 'alias') { value.include?('server1') }
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:category]).must_equal 'Host_Alias'
  #     end
  #   end
  # end

  # describe 'New helper methods' do
  #   let(:resource) { load_resource('sudoers') }

  #   it 'supports settings_by_type helper' do
  #     settings = resource.settings_by_type('user_default')
  #     _(settings).wont_be_empty
  #     _(settings.entries.first[:type]).must_equal 'user_default'
  #   end

  #   it 'supports global_defaults helper' do
  #     settings = resource.global_defaults
  #     _(settings).wont_be_empty
  #     _(settings.entries.first[:type]).must_equal 'global_default'
  #   end

  #   it 'supports all_aliases helper' do
  #     settings = resource.all_aliases
  #     _(settings).wont_be_empty
  #     _(settings.entries.first[:type]).must_equal 'alias'
  #   end
  # end

  # describe 'targeted defaults' do
  #   it 'handles user-specific defaults' do
  #     settings = resource.settings_filter.where(target_type: 'user', target: 'root')
  #     _(settings).wont_be_empty
  #     _(settings.entries.first[:setting]).must_equal 'umask'
  #     _(settings.entries.first[:value]).must_equal '027'
  #   end

  #   it 'handles command-specific defaults' do
  #     settings = resource.settings_filter.where(target_type: 'command', target: 'STORAGE')
  #     _(settings).wont_be_empty
  #     _(settings.entries.first[:setting]).must_equal 'umask'
  #   end

  #   it 'handles host-specific defaults' do
  #     settings = resource.settings_filter.where(target_type: 'host', target: 'WEBSERVERS')
  #     _(settings).wont_be_empty
  #     _(settings.entries.first[:setting]).must_equal 'ssl_verify'
  #   end

  #   it 'handles negated command defaults' do
  #     settings = resource.settings_filter.where(target_type: 'negated_command', target: 'SERVICES')
  #     _(settings).wont_be_empty
  #     _(settings.entries.first[:setting]).must_equal 'env_reset'
  #   end
  # end

  # describe 'Default bindings' do
  #   let(:resource) { load_resource('sudoers') }

  #   describe 'user bindings' do
  #     it 'handles user-specific defaults' do
  #       settings = resource.user_binding_defaults('root')
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:setting]).must_equal 'umask'
  #       _(settings.entries.first[:value]).must_equal '027'
  #       _(settings.entries.first[:binding_type]).must_equal ':'
  #     end
  #   end

  #   describe 'command bindings' do
  #     it 'handles command-specific defaults' do
  #       settings = resource.command_binding_defaults('STORAGE')
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:setting]).must_equal 'umask'
  #       _(settings.entries.first[:binding_type]).must_equal '>'
  #     end
  #   end

  #   # Similar blocks for host_bindings and negated_command_bindings
  #   # ...
  # end

  # describe 'Binding Types' do
  #   let(:resource) { load_resource('sudoers') }

  #   describe 'user bindings' do
  #     it 'handles single user defaults' do
  #       settings = resource.user_binding_defaults('root')
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:setting]).must_equal 'umask'
  #       _(settings.entries.first[:value]).must_equal '027'
  #     end

  #     it 'handles multiple settings for a user' do
  #       settings = resource.user_binding_defaults('www-data')
  #       _(settings).wont_be_empty
  #       _(settings.entries.map { |e| e[:setting] }).must_include 'umask'
  #       _(settings.entries.map { |e| e[:setting] }).must_include '!authenticate'
  #     end
  #   end

  #   describe 'command bindings' do
  #     it 'handles command defaults' do
  #       settings = resource.command_binding_defaults('STORAGE')
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:setting]).must_equal 'umask'
  #       _(settings.entries.first[:value]).must_equal '027'
  #     end
  #   end

  #   describe 'host bindings' do
  #     it 'handles host defaults' do
  #       settings = resource.host_binding_defaults('WEBSERVERS')
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:setting]).must_equal 'ssl_verify'
  #     end
  #   end

  #   describe 'negated command bindings' do
  #     it 'handles negated command defaults' do
  #       settings = resource.negated_command_defaults('SERVICES')
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:setting]).must_equal 'env_reset'
  #     end
  #   end

  #   describe 'complex binding queries' do
  #     it 'supports filtering by multiple criteria' do
  #       settings = resource.binding_defaults(type: 'user', target: 'root')
  #       _(settings).wont_be_empty
  #       _(settings.entries.first[:setting]).must_equal 'umask'
  #       _(settings.entries.first[:value]).must_equal '027'
  #     end

  #     it 'handles combined bindings' do
  #       settings = resource.settings_filter.where(
  #         type: 'binding',
  #         binding_type: 'user',
  #         binding_target: 'operator'
  #       )
  #       _(settings).wont_be_empty
  #       _(settings.entries.map { |e| e[:setting] }).must_include 'log_output'
  #     end
  #   end
  # end

  # describe 'Settings filter updates' do
  #   let(:resource) { load_resource('sudoers') }

  #   it 'includes binding_details in settings' do
  #     settings = resource.binding_details
  #     _(settings).wont_be_empty
  #     settings.each do |detail|
  #       _(detail).must_include :binding_type
  #       _(detail).must_include :binding_target
  #       _(detail).must_include :setting
  #       _(detail).must_include :value
  #       next if detail[:binding_type].nil?

  #       _(detail[:binding_type]).wont_be_nil
  #       _(detail[:binding_target]).wont_be_nil
  #       # Depending on the binding_type, setting might be optional
  #     end
  #     _(settings.first[:type]).wont_equal 'binding' # Updated expectation
  #   end

  #   it 'properly identifies binding types' do
  #     user_bindings = resource.binding_details.select { |s| s[:binding_type] == 'user' }
  #     _(user_bindings).wont_be_empty
  #     user_bindings.each do |binding|
  #       _(binding[:type]).must_equal 'user'
  #       _(binding[:binding_type]).must_equal 'user'
  #     end
  #   end

  #   it 'has a custom matcher for binding type' do
  #     assert resource.binding_details.any? { |s| s[:binding_type] == 'command' }
  #     assert resource.binding_details.any? { |s| s[:type] == 'command' }  # Added check for dynamic type
  #   end
  # end
end
