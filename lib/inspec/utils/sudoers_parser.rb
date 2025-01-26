require 'pry'  # Add for debugging

class SudoersParser
  class ParserError < StandardError; end

  DEFAULTS_QUALIFIERS = %w[: > @ !].freeze
  ALIAS_TYPES = %w[User_Alias Runas_Alias Host_Alias Cmnd_Alias].freeze
  TAGS = %w[NOPASSWD PASSWD NOEXEC EXEC SETENV NOSETENV LOG_INPUT LOG_OUTPUT MAIL NOMAIL].freeze
  OPERATORS = %w[+= -= =].freeze # Add operators list

  def initialize(content = nil)
    @content = content
  end

  def parse(content = nil)
    @content = content if content
    raise ParserError, 'No content provided' unless @content

    parse_entries(@content.split("\n"))
  end

  private

  def parse_entries(lines)
    entries = []
    current_entry = []

    lines.each do |line|
      line = strip_comments(line).strip
      next if line.empty?

      if line.end_with?('\\')
        current_entry << line.chomp('\\')
      else
        current_entry << line
        entries << parse_entry(current_entry.join(' ').strip)
        current_entry = []
      end
    end

    entries.compact
  end

  def strip_comments(line)
    line.split('#', 2).first.to_s
  end

  def parse_entry(line)
    return nil if line.empty?

    if line.start_with?('Defaults')
      parse_defaults(line)
    elsif ALIAS_TYPES.any? { |t| line.start_with?(t) }
      parse_alias(line)
    else
      parse_user_spec(line)
    end
  rescue StandardError => e
    raise ParserError, "Failed to parse line '#{line}': #{e.message}"
  end

  def parse_defaults(line)
    # Match and extract qualifier if present
    if line =~ /^Defaults\s*([>@:!]\s*\S+)?\s+(.+)$/
      qualifier = Regexp.last_match(1)
      settings = Regexp.last_match(2)

      {
        type: :defaults,
        qualifier: parse_defaults_qualifier(qualifier),
        values: parse_default_values_with_operator(settings)
      }
    end
  end

  def parse_defaults_qualifier(qualifier)
    return nil if qualifier.nil? || qualifier.empty?

    type = DEFAULTS_QUALIFIERS.find { |q| qualifier.start_with?(q) }
    return nil unless type

    target = qualifier.sub(type, '').strip
    { type:, target: }
  end

  def parse_default_values_with_operator(settings)
    # Handle quoted values with commas first
    if settings =~ /^(.+?)\s*([+\-]?=)\s*"([^"]+)"$/
      return [{
        key: Regexp.last_match(1).strip,
        value: Regexp.last_match(3).strip,
        operator: Regexp.last_match(2).strip
      }]
    end

    # Then handle multiple settings
    settings.split(/,\s*/).map do |setting|
      setting = setting.strip
      case setting
      when /^(.+?)\s*\+=\s*(.+)$/
        {
          key: Regexp.last_match(1).strip,
          value: clean_quoted_value(Regexp.last_match(2)),
          operator: '+='
        }
      when /^(.+?)\s*-=\s*(.+)$/
        {
          key: Regexp.last_match(1).strip,
          value: clean_quoted_value(Regexp.last_match(2)),
          operator: '-='
        }
      when /^(.+?)\s*=\s*(.+)$/
        {
          key: Regexp.last_match(1).strip,
          value: clean_quoted_value(Regexp.last_match(2)),
          operator: '='
        }
      else
        {
          key: setting,
          value: nil,
          operator: nil
        }
      end
    end
  end

  def clean_quoted_value(value)
    return nil if value.nil?

    # Remove surrounding quotes and handle escaped quotes
    value.strip.gsub(/^"|"$/, '').gsub(/\\"/, '"')
  end

  def parse_alias(line)
    match = line.match(/^(User_Alias|Runas_Alias|Host_Alias|Cmnd_Alias)\s+(\S+)\s*=\s*(.+)$/)
    return nil unless match

    {
      type: :alias,
      alias_type: match[1],
      name: match[2],
      members: parse_alias_members(match[3])
    }
  end

  def parse_alias_members(members_str)
    members_str.split(/,\s*/).map(&:strip)
  end

  def parse_user_spec(line)
    return nil unless line.include?('=')

    users, hosts, specs = line.split('=', 2).first.strip.split(/\s+/, 2)
    commands = line.split('=', 2).last.strip

    {
      type: :user_spec,
      users: parse_user_list(users),
      hosts: parse_host_list(hosts || 'ALL'),
      commands: parse_command_list(commands)
    }
  end

  def parse_user_list(users)
    users.split(/,\s*/).map do |user|
      {
        name: user.sub(/^%/, ''),
        is_group: user.start_with?('%')
      }
    end
  end

  def parse_host_list(hosts)
    hosts.split(/,\s*/).map(&:strip)
  end

  def parse_command_list(commands)
    commands.split(/,\s*/).map do |cmd|
      parse_command_spec(cmd.strip)
    end
  end

  def parse_command_spec(spec)
    tags = []
    runas = nil
    command = spec

    # Extract tags
    TAGS.each do |tag|
      if command.include?("#{tag}:")
        tags << tag
        command = command.sub("#{tag}:", '').strip
      end
    end

    # Extract runas specification
    if command =~ /^\((.*?)\)/
      runas = Regexp.last_match(1)
      command = command.sub(/^\((.*?)\)\s*/, '')
    end

    {
      command:,
      tags:,
      runas: runas ? parse_runas_spec(runas) : nil
    }
  end

  def parse_runas_spec(spec)
    users, groups = spec.split(':', 2).map(&:strip)
    {
      users: users ? users.split(',').map(&:strip) : ['ALL'],
      groups: groups ? groups.split(',').map(&:strip) : []
    }
  end
end
