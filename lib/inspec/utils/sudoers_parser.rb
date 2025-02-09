require 'pry'  # Add for debugging
require 'logger'
require 'strscan'
require 'ipaddr'    # For IP address validation
require 'pathname'  # For path validation
require 'resolv'    # For hostname validation
require 'set' # Add this line to fix the Set undefined error
require 'shellwords'

class SudoersParser
  class ParserError < StandardError; end

  DEFAULTS_QUALIFIERS = %w[: > @ !].freeze
  ALIAS_TYPES = %w[User_Alias Runas_Alias Host_Alias Cmnd_Alias].freeze
  TAGS = %w[NOPASSWD PASSWD NOEXEC EXEC SETENV NOSETENV LOG_INPUT LOG_OUTPUT MAIL NOMAIL].freeze
  OPERATORS = %w[+= -= =].freeze # Add operators list
  KNOWN_TAGS = %w[NOPASSWD PASSWD NOEXEC EXEC SETENV NOSETENV LOG_INPUT NOLOG_INPUT LOG_OUTPUT NOLOG_OUTPUT MAIL
                  NOMAIL].freeze
  RESERVED_WORDS = %w[ALL NOPASSWD PASSWD NOEXEC EXEC SETENV NOSETENV].freeze
  VALID_ALIAS_NAME_PATTERN = /^[A-Z][A-Z0-9_]*$/
  VALID_GROUP_PATTERN = /^%[a-zA-Z_][a-zA-Z0-9_-]*$/
  VALID_IP_PATTERN = %r{^(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:/[0-9]{1,2})?$}
  VALID_HOSTNAME_PATTERN = /^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$/
  VALID_PATH_PATTERN = %r{^/[a-zA-Z0-9/_.*-]+$}
  VALID_USER_PATTERN = /^[a-zA-Z_][a-zA-Z0-9_-]*$|^.*\\[\s1-9].*$/
  VALID_HOST_PATTERN = %r{^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$|^(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?$}
  VALID_COMMAND_PATTERN = %r{^/[a-zA-Z0-9/_.*\s-]+(?:\s+[a-zA-Z0-9/_.*\s-]+)*$}

  # RFC 952/1123 hostname validation pattern (moved from Resolv constant)
  HOSTNAME_PATTERN = /^[a-zA-Z](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)*$/

  attr_reader :parsed_data

  Token = Struct.new(:type, :value)

  def initialize(content = nil, logger = nil)
    @content = content
    @command_aliases = {} # Cache for command alias resolutions
    @parsed_data = []
    @logger = logger || Logger.new($stdout).tap do |l|
      l.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
      l.formatter = proc do |severity, datetime, _, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
    end
    @logger.debug("New SudoersParser instance initialized: #{object_id}")
    @aliases = {}
    @alias_types = {}
  end

  def parse(content = nil)
    @content = content if content
    raise ParserError, 'No content provided' unless @content

    @logger.debug("Starting parse with content length: #{@content.length}")
    begin
      @command_aliases.clear
      initial_lines = @content.split("\n")
      @logger.debug("Initial line count: #{initial_lines.length}")

      filtered_lines = initial_lines.reject { |l| strip_comments(l).strip.empty? }
      @logger.debug("Filtered line count: #{filtered_lines.length}")

      @parsed_data = parse_entries(filtered_lines)
      @logger.debug("Pre-resolution entry count: #{@parsed_data.length}")

      resolve_all_command_aliases
      @logger.debug("Final entry count: #{@parsed_data.length}")
      @logger.debug("Finished parse, parsed_data contains #{@parsed_data.length} entries")
      @parsed_data
    rescue StandardError => e
      @logger.error("Parse failed: #{e.message}")
      @logger.debug(e.backtrace.join("\n"))
      raise ParserError, "Parse failed: #{e.message}"
    end
  end

  def resolve_all_command_aliases
    @logger.debug('Starting command alias resolution pass')
    @command_aliases.clear # Clear cache before new resolution pass

    @parsed_data.each do |entry|
      next unless entry[:type] == :user_spec

      entry[:commands].each do |cmd|
        next if cmd[:resolved_commands]

        if resolved = resolve_command_alias(cmd[:command])
          cmd[:resolved_commands] = resolved
          @logger.debug("Resolved #{cmd[:command]} to #{resolved}")
        elsif resolved = resolve_command_alias(cmd[:base_command])
          cmd[:resolved_commands] = resolved
          @logger.debug("Resolved #{cmd[:base_command]} to #{resolved}")
        else
          @logger.debug("No resolution found for command: #{cmd[:command]}")
          cmd[:resolved_commands] = [cmd[:command]]
        end
      end
    end

    @logger.debug('Completed command alias resolution pass')
  end

  def add_alias(type, name, members)
    key = "#{type}:#{name}"

    # Check for alias type consistency
    if @alias_types[name] && @alias_types[name] != type
      raise ParserError, "Cannot redefine #{@alias_types[name]} '#{name}' as #{type}"
    end

    # Check for circular references before adding
    check_circular_references(type, name, members)

    @alias_types[name] = type

    # Initialize if doesn't exist or merge
    if @aliases[key]
      # Merge while preserving order and removing duplicates
      existing_members = @aliases[key][:members]
      new_members = (existing_members + members).uniq
      @aliases[key][:members] = new_members.sort
    else
      @aliases[key] = {
        type:,
        members: members.uniq.sort
      }
    end

    # Validate all members after merging
    @aliases[key][:members].each do |member|
      validate_alias_member(type, member)
    end

    @aliases[key]
  end

  private

  def check_circular_references(type, _name, members, visited = Set.new)
    members.each do |member|
      # Skip negated members and non-aliases
      next if member.start_with?('!') || !member.match?(VALID_ALIAS_NAME_PATTERN)

      if visited.include?(member)
        path = visited.to_a + [member]
        raise ParserError, "Circular reference detected: #{path.join(' -> ')}"
      end

      # Only follow references of the same type
      next unless @aliases["#{type}:#{member}"]

      visited.add(member)
      check_circular_references(type, member, @aliases["#{type}:#{member}"][:members], visited)
      visited.delete(member)
    end
  end

  def parse_entries(lines)
    entries = []
    current_line = ''
    in_continuation = false
    continuation_count = 0

    lines.each do |line|
      line = strip_comments(line).strip
      next if line.empty?

      # Handle line continuations
      if line.end_with?('\\')
        continuation_count += 1
        @logger.debug("Found continuation line #{continuation_count}: #{line}")
        # Remove backslash and normalize spaces
        current_line += "#{line.chomp('\\')} ".squeeze(' ')
        in_continuation = true
      else
        # For continued lines, append and normalize spaces
        current_line += (in_continuation ? line : line)
        current_line = current_line.squeeze(' ')

        # Only parse when we have a complete line
        unless current_line.empty?
          if entry = parse_entry(current_line.strip)
            entries << entry
          end
          current_line = ''
          in_continuation = false
        end
      end
    end

    # Handle any remaining content
    unless current_line.empty?
      current_line = current_line.squeeze(' ')
      if entry = parse_entry(current_line.strip)
        entries << entry
      end
    end

    @logger.debug("Total continuations processed: #{continuation_count}")
    entries.compact
  end

  def strip_comments(line)
    # Handle escaped hashes
    return line if line.start_with?('\\#')

    line.split('#', 2).first.to_s
  end

  def parse_entry(line)
    return nil if line.empty?

    begin
      # Check for invalid alias type before attempting to parse
      if line =~ /^(\w+_Alias)/
        alias_type = Regexp.last_match(1)
        raise ParserError, "Invalid alias type: #{alias_type} in line: #{line}" unless ALIAS_TYPES.include?(alias_type)
      end

      result = if line.start_with?('Defaults')
                 parse_defaults(line)
               elsif ALIAS_TYPES.any? { |t| line.start_with?(t) }
                 parse_alias(line)
               elsif line.include?('=')
                 parse_user_spec(line)
               else
                 raise ParserError, "Invalid sudoers entry: #{line}"
               end

      raise ParserError, "Failed to parse line: #{line}" unless result

      result
    rescue StandardError => e
      @logger.error("Failed to parse line: '#{line}'")
      @logger.error("Error: #{e.message}")
      @logger.debug(e.backtrace.join("\n"))
      raise ParserError, "Failed to parse line '#{line}': #{e.message}"
    end
  end

  def parse_defaults(line)
    case line
    when /^Defaults\s*([>@:])\s*([A-Za-z0-9_-]+)(?:\s*([>@:])\s*([A-Za-z0-9_-]+))?\s+(.+)$/ # Regular qualifiers
      qualifier_type1 = Regexp.last_match(1)
      qualifier_target1 = Regexp.last_match(2)
      qualifier_type2 = Regexp.last_match(3)
      qualifier_target2 = Regexp.last_match(4)
      settings = Regexp.last_match(5)

      qualifiers = []
      qualifiers << { type: qualifier_type1, target: qualifier_target1 }
      qualifiers << { type: qualifier_type2, target: qualifier_target2 } if qualifier_type2 && qualifier_target2

      {
        type: :defaults,
        qualifiers:,
        values: parse_default_values_with_operator(settings)
      }
    when /^Defaults!\s*([A-Za-z0-9_-]+)\s+(.+)$/ # Negative user specification (distinct from !flag)
      {
        type: :defaults,
        qualifiers: [{ type: '!', target: Regexp.last_match(1) }],
        values: parse_default_values_with_operator(Regexp.last_match(2))
      }
    when /^Defaults\s+(.+)$/ # No qualifier
      {
        type: :defaults,
        qualifiers: [],
        values: parse_default_values_with_operator(Regexp.last_match(1))
      }
    else
      raise ParserError, "Invalid defaults line: #{line}"
    end
  end

  def parse_defaults_qualifiers(qualifier_part)
    qualifiers = []
    scanner = StringScanner.new(qualifier_part)

    until scanner.eos?
      if scanner.scan(/([>@:!])\s*([A-Za-z0-9_-]+)/)
        qualifiers << {
          type: scanner[1],
          target: scanner[2]
        }
      end
      scanner.skip(/\s*/)
    end

    qualifiers
  end

  def parse_default_values_with_operator(settings)
    values = []
    scanner = StringScanner.new(settings)
    until scanner.eos?
      scanner.skip(/\s*/)
      if scanner.scan(/([^,=]+?)\s*(\+|-)?=\s*"((?:\\.|[^"])*)"/) # Fixed quote handling
        values << {
          key: scanner[1].strip,
          value: unescape_quotes(scanner[3]),
          operator: "#{scanner[2]}="
        }
      elsif scanner.scan(/([^,=]+?)\s*(\+|-)?=\s*([^,\s]+)/)
        values << {
          key: scanner[1].strip,
          value: scanner[3].strip,
          operator: "#{scanner[2]}="
        }
      elsif scanner.scan(/(!?\w+)/)
        values << {
          key: scanner[1],
          value: nil,
          operator: nil
        }
      else
        # Skip any unmatched character to prevent infinite loop
        scanner.getch
      end
      scanner.skip(/\s*,?\s*/)
    end
    values
  end

  def unescape_quotes(str)
    str.gsub(/\\(.)/) { Regexp.last_match(1) }
  end

  def clean_quoted_value(value)
    return nil if value.nil?

    # Remove surrounding quotes and handle escaped quotes
    value.strip.gsub(/^"|"$/, '').gsub(/\\"/, '"')
  end

  def tokenize_alias_line(line)
    tokens = []
    scanner = StringScanner.new(line)

    # Match alias type
    tokens << Token.new(:ALIAS_TYPE, scanner.matched.strip) if scanner.scan(/(User|Runas|Host|Cmnd)_Alias\s+/)

    # Match alias name
    tokens << Token.new(:ALIAS_NAME, scanner.matched.strip) if scanner.scan(/[A-Z][A-Z0-9_]*\s*/)

    # Match equals sign
    tokens << Token.new(:EQUALS, '=') if scanner.scan(/=\s*/)

    # Match members
    until scanner.eos?
      if scanner.scan(/\s*,\s*/)
        tokens << Token.new(:COMMA, ',')
      elsif scanner.scan(/!\s*/)
        tokens << Token.new(:NOT, '!')
      elsif scanner.scan(/[^,\s]+/)
        tokens << Token.new(:WORD, scanner.matched.strip)
      elsif scanner.scan(/\s+/)
        # Skip whitespace
      else
        raise ParserError, "Invalid token in alias definition: #{scanner.rest}"
      end
    end

    tokens
  end

  def parse_alias(line)
    tokens = tokenize_alias_line(line)
    state = :start
    alias_type = nil
    alias_name = nil
    members = []

    tokens.each do |token|
      case state
      when :start
        raise ParserError, 'Expected ALIAS_TYPE' unless token.type == :ALIAS_TYPE

        alias_type = token.value
        state = :need_name

      when :need_name
        raise ParserError, 'Expected ALIAS_NAME' unless token.type == :ALIAS_NAME

        validate_alias_name(token.value)
        alias_name = token.value
        state = :need_equals

      when :need_equals
        raise ParserError, 'Expected EQUALS' unless token.type == :EQUALS

        state = :need_member

      when :need_member
        case token.type
        when :WORD
          validate_alias_member(alias_type, token.value)
          members << token.value
          state = :got_member
        when :NOT
          state = :need_negated_member
        else
          raise ParserError, 'Expected member or negation'
        end

      when :need_negated_member
        raise ParserError, 'Expected member after negation' unless token.type == :WORD

        validate_alias_member(alias_type, token.value)
        members << "!#{token.value}"
        state = :got_member

      when :got_member
        case token.type
        when :COMMA
          state = :need_member
        else
          raise ParserError, 'Expected comma between members'
        end
      end
    end

    raise ParserError, 'Incomplete alias definition' unless %i[got_member need_member].include?(state)

    add_alias(alias_type, alias_name, members)

    {
      type: :alias,
      alias_type:,
      name: alias_name,
      members: members.sort # Ensure consistent ordering
    }
  end

  def parse_alias_members(members_str)
    scanner = StringScanner.new(members_str)
    members = []
    current = ''
    in_escape = false

    until scanner.eos?
      char = scanner.getch
      if in_escape
        current << char
        in_escape = false
      elsif char == '\\'
        in_escape = true
      elsif char == ',' && !in_escape
        members << clean_member(current) unless current.empty?
        current = ''
      else
        current << char
      end
    end
    members << clean_member(current) unless current.empty?
    members
  end

  def clean_member(member)
    # Remove leading/trailing spaces and handle escapes
    member.strip.gsub(/\\(.)/, '\1')
  end

  def unescape_member(member)
    member.gsub(/\\(.)/) { Regexp.last_match(1) }
  end

  def validate_alias_name(name)
    raise ParserError, "Invalid alias name: #{name}" if name.nil? || name.empty?
    raise ParserError, "Reserved word used as alias name: #{name}" if RESERVED_WORDS.include?(name)

    # More descriptive error message for invalid alias names
    unless name =~ VALID_ALIAS_NAME_PATTERN
      if name =~ /^[^A-Z]/
        raise ParserError, "Alias name must start with uppercase letter: #{name}"
      elsif name =~ /[^A-Z0-9_]/
        raise ParserError, "Alias name can only contain uppercase letters, numbers and underscores: #{name}"
      else
        raise ParserError, "Invalid alias name format: #{name}"
      end
    end
  end

  def validate_alias_members(type, members)
    members.each do |member|
      validate_member(type, member)
      check_cross_reference(type, member) if member =~ VALID_ALIAS_NAME_PATTERN
    end
  end

  def validate_member(type, member)
    case type
    when 'User_Alias'
      raise ParserError, "Invalid user alias member: #{member}" unless valid_user_member?(member)
    when 'Cmnd_Alias'
      unless valid_command_member?(member) || member == 'ALL'
        raise ParserError, "Invalid command alias member: #{member}"
      end
    when 'Host_Alias'
      raise ParserError, "Invalid host alias member: #{member}" unless valid_host_member?(member) || member == 'ALL'
    end
  end

  def check_cross_reference(_type, member)
    return unless member =~ VALID_ALIAS_NAME_PATTERN
    return unless @alias_types[member] # Only check if member is a known alias

    # Allow ALL as a special case
    return if member == 'ALL'

    # Only check cross references within the same alias type
    # This means ADMINS can be used in Host_Alias even if defined as User_Alias
    true
  end

  def validate_alias_member(type, member)
    return if member == 'ALL'

    # Handle negated members
    actual_member = member.start_with?('!') ? member[1..] : member

    case type
    when 'User_Alias'
      raise ParserError, "Invalid user alias member: #{actual_member}" unless valid_user_member?(actual_member)
    when 'Cmnd_Alias'
      raise ParserError, "Invalid command alias member: #{actual_member}" unless valid_command_member?(actual_member)
    when 'Host_Alias'
      raise ParserError, "Invalid host alias member: #{actual_member}" unless valid_host_member?(actual_member)
    when 'Runas_Alias'
      raise ParserError, "Invalid runas alias member: #{actual_member}" unless valid_user_member?(actual_member)
    end

    check_alias_reference(type, actual_member) if actual_member =~ VALID_ALIAS_NAME_PATTERN
  end

  def check_alias_reference(type, member)
    return unless @alias_types[member]
    return if member == 'ALL'

    raise ParserError, "Cannot use #{@alias_types[member]} '#{member}' in #{type}" if @alias_types[member] != type
  end

  def valid_user_member?(member)
    return true if member == 'ALL'
    return true if member =~ VALID_GROUP_PATTERN # %group format
    return true if member =~ /^[a-zA-Z_][a-zA-Z0-9_-]*$/ # Regular username
    return true if member =~ /^@[a-zA-Z][a-zA-Z0-9_-]*$/ # @group format
    # Handle escaped usernames including spaces
    return true if member =~ /^[a-zA-Z0-9_][a-zA-Z0-9_ -]*$/ # Allow spaces in escaped usernames

    false
  end

  def valid_host_member?(member)
    return true if member == 'ALL'
    # Try as IP address or CIDR first
    return true if member =~ %r{^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$}
    # Try as hostname - Allow only valid hostname characters
    return true if member =~ /^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$/

    false
  end

  def valid_command_member?(member)
    return true if member == 'ALL'

    path, *args = member.split(/\s+/)
    begin
      pathname = Pathname.new(path)
      return false unless pathname.absolute?

      # Validate path components and allow wildcards
      path_valid = path.split('/').all? do |part|
        next true if part.empty? # Allow consecutive slashes

        part =~ /^[a-zA-Z0-9_.*-]+$/
      end

      # Validate arguments if present
      args_valid = args.all? { |arg| valid_command_argument?(arg) }

      path_valid && args_valid
    rescue ArgumentError
      false
    end
  end

  def valid_command_argument?(arg)
    return true if arg.start_with?('-')   # Options
    return true if arg.start_with?('/')   # Paths
    return true if arg =~ /[*?]/ # Wildcards
    return true if arg =~ /^[a-zA-Z0-9._-]+$/ # Regular arguments

    false
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

    # Extract tags first
    while command.match(/(\w+):/)
      tag = Regexp.last_match(1)
      if KNOWN_TAGS.include?(tag)
        found_tags << tag
        command.sub!(/#{tag}:/, '')
      else
        @logger.warn("Unknown tag found: #{tag}")
      end
      command = command.strip
    end

    begin
      if command.match?(/^".*"$|^'.*'$/) # Fully quoted command with spaces
        parts = Shellwords.split(command)
        base_command = parts.first.gsub(/^['"]|['"]$/, '')
        if base_command.include?(' ') # Handle spaces in base command path
          base_command = base_command.split.first # Get just the path portion
        end
        arguments = parts[1..-1] || []
        command_str = command
      else
        parts = command.split(/\s+/)
        base_command = parts.first.gsub(/\\(.)/, '\1')
        arguments = parts[1..-1] || []
        command_str = command
      end

      # Single resolution call with original command
      resolved = resolve_command_alias(command_str)

      {
        command: command_str.strip,
        base_command:,
        arguments: arguments.reject(&:empty?),
        tags: found_tags,
        runas: runas ? parse_runas_spec(runas) : nil,
        resolved_commands: resolved
      }
    rescue ArgumentError => e
      @logger.warn("Command parsing failed: #{e.message}, using raw command")
      parts = command.split(/\s+/, 2)
      {
        command:,
        base_command: parts.first,
        arguments: parts[1] ? [parts[1]] : [],
        tags: found_tags,
        runas: runas ? parse_runas_spec(runas) : nil,
        resolved_commands: resolve_command_alias(parts.first)
      }
    end
  end

  def split_quoted_command(command)
    Shellwords.split(command)
  rescue ArgumentError
    command.split(/\s+/) # Fallback to simple splitting if Shellwords fails
  end

  def split_escaped_command(command)
    current_part = ''
    parts = []
    in_quotes = false
    quote_char = nil
    escaped = false

    command.each_char do |c|
      if escaped
        current_part << c
        escaped = false
      elsif c == '\\'
        escaped = true
      elsif ['"', "'"].include?(c)
        if !in_quotes
          in_quotes = true
          quote_char = c
        elsif c == quote_char
          in_quotes = false
          quote_char = nil
        else
          current_part << c
        end
      elsif c == ' ' && !in_quotes
        parts << current_part unless current_part.empty?
        current_part = ''
      else
        current_part << c
      end
    end

    parts << current_part unless current_part.empty?
    parts
  end

  def parse_remaining_args(args_str)
    return [] if args_str.empty?

    args = []
    current_arg = ''
    in_quotes = false
    escaped = false

    args_str.each_char do |c|
      if escaped
        current_arg << c
        escaped = false
      elsif c == '\\'
        escaped = true
        current_arg << c
      elsif c == '"'
        in_quotes = !in_quotes
        current_arg << c
      elsif c == ' ' && !in_quotes
        args << current_arg unless current_arg.empty?
        current_arg = ''
      else
        current_arg << c
      end
    end

    args << current_arg unless current_arg.empty?
    args
  end

  def parse_quoted_args(args_str)
    args = []
    current_arg = ''
    in_quotes = false
    escaped = false

    args_str.each_char do |c|
      if escaped
        current_arg << c
        escaped = false
      elsif c == '\\'
        escaped = true
        current_arg << c
      elsif c == '"'
        if !in_quotes
          in_quotes = true
          current_arg << c unless current_arg.empty?
        else
          in_quotes = false
          current_arg << c
        end
      elsif c == ' ' && !in_quotes
        args << current_arg unless current_arg.empty?
        current_arg = ''
      else
        current_arg << c
      end
    end

    args << current_arg unless current_arg.empty?
    args
  end

  def resolve_command_alias(command_name, visited = Set.new)
    return nil unless command_name
    return nil if command_name == 'ALL' # Special case

    # Extract base command for resolution
    base_command = command_name.split.first.gsub(/^['"]|['"]$/, '')

    # Check cache first
    return @command_aliases[base_command] if @command_aliases.key?(base_command)

    # Detect circular references
    if visited.include?(base_command)
      @logger.warn("Circular command alias reference detected: #{visited.to_a.join(' -> ')} -> #{base_command}")
      return nil
    end

    # Find direct alias entry
    alias_entry = @parsed_data&.find do |entry|
      entry[:type] == :alias &&
        entry[:alias_type] == 'Cmnd_Alias' &&
        entry[:name] == base_command
    end

    if alias_entry
      visited.add(base_command)

      # Recursively resolve nested aliases
      resolved_commands = alias_entry[:members].flat_map do |member|
        if member =~ VALID_ALIAS_NAME_PATTERN && !visited.include?(member)
          # Recursively resolve nested alias
          nested_resolution = resolve_command_alias(member, visited) || [member]
          nested_resolution
        else
          # Return direct command
          [member]
        end
      end.uniq.sort

      visited.delete(base_command)

      # Cache the fully resolved result
      @command_aliases[base_command] = resolved_commands
      @logger.debug("Cached command alias resolution for #{base_command}: #{resolved_commands}")

      resolved_commands
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

      # Filter out negated users from all_users but keep them in original_users
      all_users.concat(parsed_users.reject { |u| u.start_with?('!') }.map { |u| u.gsub(/\\/, '') })
      all_groups.concat(parsed_groups.reject { |g| g.start_with?('!') }.map { |g| g.gsub(/\\/, '') })
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

  def valid_command_argument?(arg)
    # Allow common argument patterns:
    # - Regular arguments starting with - (options)
    # - Paths starting with /
    # - Patterns with * or ?
    # - Regular words/numbers
    return true if arg.start_with?('-')   # Options
    return true if arg.start_with?('/')   # Paths
    return true if arg =~ /[*?]/ # Wildcards
    return true if arg =~ /^[a-zA-Z0-9._-]+$/  # Regular arguments

    false
  end
end
