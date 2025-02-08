require 'pry'  # Add for debugging
require 'logger'

class SudoersParser
  class ParserError < StandardError; end

  DEFAULTS_QUALIFIERS = %w[: > @ !].freeze
  ALIAS_TYPES = %w[User_Alias Runas_Alias Host_Alias Cmnd_Alias].freeze
  TAGS = %w[NOPASSWD PASSWD NOEXEC EXEC SETENV NOSETENV LOG_INPUT LOG_OUTPUT MAIL NOMAIL].freeze
  OPERATORS = %w[+= -= =].freeze # Add operators list
  KNOWN_TAGS = %w[NOPASSWD PASSWD NOEXEC EXEC SETENV NOSETENV LOG_INPUT NOLOG_INPUT LOG_OUTPUT NOLOG_OUTPUT MAIL
                  NOMAIL].freeze

  def initialize(content = nil, logger = nil)
    @content = content
    @parsed_data = [] # Initialize parsed_data array
    @logger = logger || Logger.new($stdout).tap do |log|
      log.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
      log.formatter = proc do |severity, datetime, _, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
    end
  end

  def parse(content = nil)
    @content = content if content
    raise ParserError, 'No content provided' unless @content

    @parsed_data = parse_entries(@content.split("\n")) # Store parsed entries
    @parsed_data # Return parsed data
  end

  private

  def parse_entries(lines)
    entries = []
    in_continuation = false
    joined_line = ''

    lines.each do |line|
      line = strip_comments(line).strip
      next if line.empty?

      if line.end_with?('\\')
        in_continuation = true
        joined_line += "#{line.chomp('\\')} "
      elsif in_continuation
        joined_line += line
        unless line.end_with?('\\')
          entries << parse_entry(joined_line.strip)
          joined_line = ''
          in_continuation = false
        end
      else
        entries << parse_entry(line)
      end
    end

    entries << parse_entry(joined_line.strip) if in_continuation
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
    { type: type, target: target } # rubocop:disable Style/HashSyntax
  end

  def parse_default_values_with_operator(settings)
    # Handle multi-line quoted values first
    if settings =~ /^(.+?)\s*([+\-]?=)\s*"([^"]+(?:\\.[^"]+)*)"$/
      key = Regexp.last_match(1).strip
      operator = Regexp.last_match(2).strip
      value = Regexp.last_match(3)
      value = value.gsub(/\\(.)/, '\1') # Unescape special chars

      return [{
        key: key, # rubocop:disable Style/HashSyntax
        value: value, # rubocop:disable Style/HashSyntax
        operator: operator # rubocop:disable Style/HashSyntax
      }]
    end

    # Then handle multiple settings
    settings.split(/,\s*(?=(?:[^"]*"[^"]*")*[^"]*$)/).map do |setting|
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

    # Split into users, hosts, and remaining spec
    parts = line.match(/^(\S+)\s+([^=]+?)=(.+)$/)
    return nil unless parts

    users, hosts, remaining = parts.captures

    # Extract RunAs and commands from remaining
    runas = nil
    commands = remaining

    # Handle RunAs specification
    if remaining =~ /^\s*\(([^)]+)\)\s*(.+)$/
      runas = Regexp.last_match(1)
      commands = Regexp.last_match(2)
    end

    {
      type: :user_spec,
      users: parse_user_list(users),
      hosts: parse_host_list(hosts || 'ALL'),
      commands: parse_command_list(commands, runas)
    }
  end

  def parse_command_list(commands, runas = nil)
    commands.split(/,\s*/).map do |cmd|
      parse_command_spec(cmd.strip, runas)
    end
  end

  def parse_command_spec(spec, runas = nil)
    command = spec.strip
    found_tags = []

    @logger.debug("Command Spec Processing - Input spec: #{spec.inspect}")

    # Extract tags in order of appearance
    original_spec = command.dup
    while original_spec.match(/(\w+):/)
      tag = Regexp.last_match(1)
      if KNOWN_TAGS.include?(tag)
        found_tags << tag
        original_spec.sub!(/#{tag}:/, '') # Remove the matched tag
      else
        @logger.warn("Unknown tag found: #{tag}")
      end
      original_spec = original_spec.strip
    end

    command = original_spec.strip
    @logger.debug("Found tags: #{found_tags.inspect}")
    @logger.debug("Command after tag removal: #{command}")

    # Parse command and arguments
    parts = if command.include?('"') || command.include?("'")
              parse_quoted_command(command)
            else
              parse_pattern_command(command)
            end

    base_command = parts.first&.gsub(/\\(.)/, '\1')
    arguments = parts.length > 1 ? parts[1..-1].map { |arg| arg.strip.gsub(/\\(.)/, '\1') } : []

    # Check for command alias resolution
    if command_alias = resolve_command_alias(base_command)
      @logger.debug("Found command alias: #{base_command} -> #{command_alias.inspect}")
      {
        command: command, # rubocop:disable Style/HashSyntax
        base_command: base_command, # rubocop:disable Style/HashSyntax
        arguments: arguments, # rubocop:disable Style/HashSyntax
        tags: found_tags,
        runas: runas ? parse_runas_spec(runas) : nil,
        resolved_commands: command_alias
      }
    else
      @logger.debug("No command alias found for: #{base_command}")
      {
        command: command, # rubocop:disable Style/HashSyntax
        base_command: base_command, # rubocop:disable Style/HashSyntax
        arguments: arguments, # rubocop:disable Style/HashSyntax
        tags: found_tags,
        runas: runas ? parse_runas_spec(runas) : nil
      }
    end
  end

  def resolve_command_alias(command_name)
    return nil unless command_name

    @logger.debug("Looking up command alias: #{command_name}")
    @logger.debug("Current parsed data: #{@parsed_data.inspect}")

    alias_entry = @parsed_data&.find do |entry|
      entry[:type] == :alias &&
        entry[:alias_type] == 'Cmnd_Alias' &&
        entry[:name] == command_name
    end

    if alias_entry
      @logger.debug("Found alias entry: #{alias_entry.inspect}")
      alias_entry[:members]
    else
      @logger.debug("No alias entry found for: #{command_name}")
      nil
    end
  end

  def parse_pattern_command(command)
    parts = []
    current_part = ''
    state = {
      in_pattern: false,
      pattern_depth: 0,
      escaped: false
    }

    @logger.debug("Parsing pattern command: #{command.inspect}")

    command.each_char do |c|
      if state[:escaped]
        current_part << c
        state[:escaped] = false
        next
      end

      case c
      when '\\'
        state[:escaped] = true
        current_part << c
      when '['
        state[:in_pattern] = true
        state[:pattern_depth] += 1
        current_part << c
      when ']'
        state[:pattern_depth] -= 1
        current_part << c
        state[:in_pattern] = false if state[:pattern_depth] == 0
      when '*', '?'
        # Always treat glob characters as part of the current part
        current_part << c
      when ' '
        if state[:in_pattern]
          current_part << c
        else
          parts << current_part unless current_part.empty?
          current_part = ''
        end
      else
        current_part << c
      end
    end

    parts << current_part unless current_part.empty?

    @logger.debug("Pattern command parts: #{parts.inspect}")
    parts
  end

  # Add pattern matching helper method
  def pattern_matches?(pattern, string)
    require 'pathname'

    # First use our existing parser to handle sudoers-specific patterns
    return true if pattern == string

    # Then fall back to File::FNM for standard glob patterns
    File.fnmatch?(pattern, string, File::FNM_PATHNAME | File::FNM_EXTGLOB)
  rescue StandardError => e
    @logger.warn("Pattern matching failed: #{e.message}")
    false
  end

  def parse_user_list(users)
    users.split(/,\s*/).map do |user|
      {
        name: user.sub(/^%/, '').gsub(/[\\*]/, ''), # Remove % and escape chars for name
        is_group: user.start_with?('%'),
        original: user.strip # Preserve original with wildcards and escapes
      }
    end
  end

  def parse_host_list(hosts)
    hosts.split(/,\s*/).map(&:strip)
  end

  def parse_quoted_command(command)
    @logger.warn("Found empty quotes in command: #{command}") if command.include?('""') || command.include?("''")

    parts = []
    current = ''
    state = {
      in_quotes: false,
      quote_char: nil,
      escaped: false,
      in_pattern: false,
      pattern_depth: 0
    }

    command.each_char do |c|
      if state[:escaped]
        current << c
        state[:escaped] = false
        next
      end

      case c
      when '\\'
        state[:escaped] = true
        current << c
      when '"', "'"
        if !state[:in_quotes]
          state[:in_quotes] = true
          state[:quote_char] = c
        elsif c == state[:quote_char]
          state[:in_quotes] = false
          state[:quote_char] = nil
        else
          # Handle nested quotes
          current << c
        end
      when '['
        unless state[:in_quotes]
          state[:in_pattern] = true
          state[:pattern_depth] += 1
        end
        current << c
      when ']'
        unless state[:in_quotes]
          state[:pattern_depth] -= 1
          state[:in_pattern] = false if state[:pattern_depth] == 0
        end
        current << c
      when ' '
        if state[:in_quotes] || state[:in_pattern]
          current << c
        else
          parts << current unless current.empty?
          current = ''
        end
      else
        current << c
      end
    end

    parts << current unless current.empty?

    # Clean up escaped characters but preserve empty quotes
    parts.map do |part|
      clean_part = part.gsub(/\\(.)/, '\1') # Unescape characters
      if clean_part.match?(/^["'].*["']$/) && !clean_part.match?(/^(["']).*\1$/)
        # Add missing closing quote if needed
        clean_part + clean_part[0]
      else
        clean_part
      end
    end
  end

  def parse_runas_spec(spec)
    # Handle multiple RunAs specifications with groups
    specs = spec.include?(',') ? spec.split(/,(?![^()]*\))/) : [spec]

    all_users = []
    all_groups = []
    original_users = []
    original_groups = []

    specs.each do |single_spec|
      users, groups = single_spec.split(':', 2).map(&:strip)
      parsed_users = users ? users.split(',').map(&:strip) : ['ALL']
      parsed_groups = groups ? groups.split(',').map(&:strip) : []

      all_users.concat(parsed_users.map { |u| u.gsub(/\\/, '') }) # Preserve wildcards
      all_groups.concat(parsed_groups.map { |g| g.gsub(/\\/, '') })
      original_users.concat(parsed_users)
      original_groups.concat(parsed_groups)
    end

    {
      users: all_users.uniq,
      groups: all_groups.uniq,
      original_users: original_users.uniq,
      original_groups: original_groups.uniq
    }
  end
end
