module Inspec::Resources
  # This class is responsible for filtering and managing sudoers rules.
  class SudoersRulesFilter
    filter = FilterTable.create
    filter.register_custom_matcher(:exists?) { |x| !x.entries.empty? }
    filter.register_column(:users, field: :users)
    filter.register_column(:hosts, field: :hosts)
    filter.register_column(:run_as, field: :run_as)
    filter.register_column(:tags, field: :tags)
    filter.register_column(:commands, field: :commands)
    filter.register_custom_matcher(:nopasswd?) { |x| x.tags && x.tags.include?("NOPASSWD:") }
    filter.install_filter_methods_on_resource(self, :table)

    attr_reader :table

    def initialize(table)
      @table = table
    end

    def to_s
      "Sudoers Rules"
    end
  end

  # This class is responsible for filtering and managing sudoers settings.
  class SudoersSettingsFilter
    filter = FilterTable.create
    filter.register_custom_matcher(:exists?) { |x| !x.entries.empty? }
    filter.register_column(:names, field: :name)
    filter.register_column(:values, field: :value)
    filter.install_filter_methods_on_resource(self, :settings)

    attr_reader :settings

    def initialize(settings)
      @settings = settings
    end

    def to_s
      "Sudoers Settings"
    end
  end

  # This class represents the sudoers resource in InSpec, used to test sudo configuration.
  class Sudoers < Inspec.resource(1)
    name "sudoers"
    supports platform: "unix"
    supports platform: "darwin"
    supports platform: "freebsd"
    supports platform: "solaris"
    supports platform: "aix"
    desc "Use the sudoers InSpec audit resource to test the configuration of sudo."
    example <<~EXAMPLE
      # Test that there are no NOPASSWD rules
      describe sudoers.rules.where { !tags.nil? && tags.include?('NOPASSWD:') } do
        it { should_not exist }
      end

      # Test timeout setting
      describe sudoers.settings.where(name: 'timestamp_timeout') do
        its('values') { should cmp 0 }
      end
    EXAMPLE

    attr_reader :lines, :settings, :sudoers_files, :raw_content, :table

    # List of directives to be ignored during parsing
    # Add any new directives that should be ignored to this list
    # consider adding a test to ensure the directive is ignored
    # consider adding a warning if the directive is not ignored
    # TODO: add a way for the user to pass a directive to ignore to the resource & add tests
    IGNORED_DIRECTIVES = ["#includedir"].freeze

    def initialize(sudoers_files = nil)
      super()
      @sudoers_files = [sudoers_files || default_sudoers_path].flatten
      Inspec::Log.debug("sudoers_files: #{@sudoers_files}")

      if @sudoers_files.empty?
        Inspec::Log.warn("No sudoers files found. Skipping resource.")
        skip_resource "No sudoers files found."
      end

      load_content
      parse_content
    end

    def rules
      @table
    end

    def resource_id
      @sudoers_files.first || default_sudoers_path
    end

    def to_s
      "Sudoers Configuration #{@sudoers_files.join(", ")}"
    end

    # Helper methods
    def authenticate?
      settings.Defaults.include?("!authenticate")
    end

    def timeout_value
      timeout = settings.Defaults["timestamp_timeout"]
      timeout ? timeout.first.to_i : nil
    end

    def timeout_value?
      !timeout_value.nil?
    end

    def user_aliases
      settings.where(name: "User_Alias")
    end

    def command_aliases
      settings.where(name: "Cmnd_Alias")
    end

    def defaults
      settings.where(name: "Defaults")
    end

    def user_defaults(user)
      settings.where(name: "Defaults:#{user}")
    end

    private

    def default_sudoers_path
      path = case inspec.os.name
             when "darwin"
               "/private/etc/sudoers"
             when "freebsd"
               "/usr/local/etc/sudoers"
             when "solaris"
               "/etc/opt/sudoers"
             when "aix"
               "/etc/security/sudoers"
             else
               "/etc/sudoers"
             end

      Inspec::Log.warn("Default sudoers path #{path} does not exist.") unless inspec.file(path).exist?

      path
    end

    def load_content
      @raw_content = inspec.command("cat #{@sudoers_files.join(" ")}").stdout
      if @raw_content.empty?
        Inspec::Log.warn("Failed to load content from sudoers files: #{@sudoers_files.join(", ")}")
        skip_resource "Failed to load content from sudoers files."
      end
      Inspec::Log.debug("raw_content: #{@raw_content}")
      @lines = @raw_content.lines.reject do |line|
        line.nil? || line.match(/^#(?!include)|^\s*$/) || IGNORED_DIRECTIVES.any? do |directive|
          line.include?(directive)
        end
      end.map(&:strip)
      Inspec::Log.debug("lines: #{@lines}")
    end

    def parse_content
      aliases = %w{Defaults Cmnd_Alias User_Alias Host_Alias Runas_Alias}
      settings_lines = @lines.select { |line| line.match(/^(#{aliases.join('|')})/) }
      userspec_lines = @lines.reject { |line| line.match(/^(#{aliases.join('|')})/) }
      Inspec::Log.debug("settings_lines: #{settings_lines}")
      Inspec::Log.debug("userspec_lines: #{userspec_lines}")
      # TODO: The resource is currently trying to access this like its a filter table from the
      # SudoersRulesFilter class. This is incorrect and should be fixed.
      @settings = settings_hash(settings_lines) # Store as instance var
      @table = SudoersUserSpecTable.new(userspec_lines)
      Inspec::Log.debug("@table: #{@table.table}")
    end

    def settings_hash(settings_lines)
      parse_options = {
        assignment_regex: /^\s*([^=]*?)\s*\+?=\s*(.*?)\s*$/,
        multiple_values: true,
      }
      sudo_config_data = inspec.parse_config(settings_lines.join("\n"), parse_options).params
      sudo_config_hash = Hashie::Mash.new
      sudo_config_data.each do |k, v|
        if k.start_with?("Defaults")
          key_parts = k.split("\s", 2)
          sudo_config_hash.Defaults ||= Hashie::Mash.new
          sudo_config_hash.Defaults[key_parts[1].strip] = v.map { |x| x.delete('"').split(/,\s*/) }.flatten
        else
          key_parts = k.split("\s")
          sudo_config_hash[key_parts[0]] ||= Hashie::Mash.new
          sudo_config_hash[key_parts[0]][key_parts[1]] = v.map { |x| x.delete('"').split(/,\s*/) }.flatten
        end
      end
      sudo_config_hash
    end
  end
end

# This class is responsible for parsing and filtering user specifications in the sudoers file.
class SudoersUserSpecTable
  FilterTable.create
    .register_column(:users, field: :users)
    .register_column(:hosts, field: :hosts)
    .register_column(:run_as, field: :run_as)
    .register_column(:tags, field: :tags)
    .register_column(:commands, field: :commands)
    .install_filter_methods_on_resource(self, :table)

  attr_reader :table

  def initialize(userspec_lines)
    Inspec::Log.debug("Initializing SudoersUserSpecTable with userspec_lines: #{userspec_lines}")
    tags = %w{NOPASSWD PASSWD NOEXEC EXEC SETENV NOSETENV LOG_INPUT NOLOG_INPUT LOG_OUTPUT
              NOLOG_OUTPUT}
    @table = userspec_lines.map.with_index do |line, index|
      line_hash = {}
      parsed_line = line.match(/^(?<users>\S+)\s+(?<hosts>[^\s=]+)\s*=\s*(\((?<run_as>[^)]+)\))?\s*(?<tags>(#{tags.join(':|')}:)+)?\s*(?<commands>.*)$/)
      Inspec::Log.debug("Line #{index + 1}: #{line}")
      if parsed_line.nil?
        Inspec::Log.warn("Unable to parse line #{index + 1}: #{line}")
      else
        Inspec::Log.debug("parsed_line: #{parsed_line}")
        line_hash[:users] = parsed_line["users"]
        line_hash[:hosts] = parsed_line["hosts"]
        line_hash[:run_as] = parsed_line["run_as"] unless parsed_line["run_as"].nil?
        line_hash[:tags] = parsed_line["tags"] unless parsed_line["tags"].nil?
        line_hash[:commands] = parsed_line["commands"]
        line_hash.transform_values! { |v| !v.nil? && v.include?(",") ? v.split(",") : v }
      end
      line_hash unless line_hash.empty?
    end.compact
    Inspec::Log.debug("@table: #{@table}")
  end

  def to_s
    "Sudoers User Permissions Table"
  end
end
