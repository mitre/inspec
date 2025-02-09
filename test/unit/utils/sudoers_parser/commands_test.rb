require 'minitest/autorun'
require 'stringio'
require 'logger'
require_relative '../../../../lib/inspec/utils/sudoers_parser'

class SudoersParserCommandsTest < Minitest::Test
  def setup
    @debug_output = StringIO.new
    @logger = Logger.new(@debug_output).tap do |l|
      l.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
    end
    @parser = SudoersParser.new(nil, @logger)
  end

  def test_basic_command_parsing
    content = <<~SUDOERS
      admin ALL=(root) /usr/bin/less
    SUDOERS

    result = @parser.parse(content)
    command = result.first[:commands].first

    assert_equal '/usr/bin/less', command[:command]
    assert_equal '/usr/bin/less', command[:base_command]
    assert_equal [], command[:arguments]
    assert_equal [], command[:tags]
  end

  def test_command_with_arguments
    content = <<~SUDOERS
      admin ALL=(root) /usr/bin/kill -9
    SUDOERS

    result = @parser.parse(content)
    command = result.first[:commands].first

    assert_equal '/usr/bin/kill -9', command[:command]
    assert_equal '/usr/bin/kill', command[:base_command]
    assert_equal ['-9'], command[:arguments]
  end

  def test_command_with_pattern
    content = <<~SUDOERS
      admin ALL=(ALL) /usr/bin/passwd [A-Za-z]*
    SUDOERS

    result = @parser.parse(content)
    command = result.first[:commands].first

    assert_equal '/usr/bin/passwd [A-Za-z]*', command[:command]
    assert_equal '/usr/bin/passwd', command[:base_command]
    assert_equal ['[A-Za-z]*'], command[:arguments]
  end

  def test_command_with_tags
    content = <<~SUDOERS
      admin ALL=(root) NOPASSWD:NOEXEC: /usr/bin/less
    SUDOERS

    result = @parser.parse(content)
    command = result.first[:commands].first

    assert_equal '/usr/bin/less', command[:command]
    assert_equal %w[NOPASSWD NOEXEC], command[:tags]
  end

  def test_command_with_escaped_characters
    content = <<~SUDOERS
      dev_* ALL=(ALL) /usr/bin/\\ls
    SUDOERS

    result = @parser.parse(content)
    command = result[0][:commands][0]

    # Escapes should be preserved in command but removed in base_command
    assert_equal '/usr/bin/\\ls', command[:command]
    assert_equal '/usr/bin/ls', command[:base_command]
  end

  def test_command_with_multiple_arguments
    content = <<~SUDOERS
      admin ALL=(ALL) "/usr/bin/find" "/var" "-name" "*.log"
    SUDOERS

    result = @parser.parse(content)
    command = result.first[:commands].first

    # Each argument should be separately quoted per sudoers spec
    assert_equal '/usr/bin/find', command[:base_command]
    assert_equal ['/var', '-name', '*.log'], command[:arguments]
  end

  def test_command_with_quotes
    content = <<~SUDOERS
      admin ALL=(ALL) /bin/echo "Hello World"
      admin ALL=(ALL) /bin/cat '/etc/passwd'
    SUDOERS

    result = @parser.parse(content)
    commands = result.map { |e| e[:commands].first }

    assert_equal ['/bin/echo', 'Hello World'], [commands[0][:base_command], commands[0][:arguments].first]
    assert_equal ['/bin/cat', '/etc/passwd'], [commands[1][:base_command], commands[1][:arguments].first]
  end

  def test_command_with_multiple_options
    content = <<~SUDOERS
      admin ALL=(ALL) /usr/bin/vim /[a-z]*/*, /usr/bin/nano /[a-z]*/config
    SUDOERS

    result = @parser.parse(content)
    commands = result.first[:commands]

    assert_equal 2, commands.length
    assert_equal '/usr/bin/vim', commands[0][:base_command]
    assert_equal '/usr/bin/nano', commands[1][:base_command]
    assert_equal ['/[a-z]*/*'], commands[0][:arguments]
    assert_equal ['/[a-z]*/config'], commands[1][:arguments]
  end

  def test_command_with_complex_patterns
    content = <<~SUDOERS
      admin ALL=(ALL) /usr/bin/find "/path with spaces/[0-9]*" -name "*.txt"
      backup ALL=(ALL) /usr/bin/rsync --server *
    SUDOERS

    result = @parser.parse(content)
    commands = result.map { |e| e[:commands].first }

    assert_equal '/usr/bin/find', commands[0][:base_command]
    assert_equal ['/path with spaces/[0-9]*', '-name', '*.txt'], commands[0][:arguments]
    assert_equal '/usr/bin/rsync', commands[1][:base_command]
    assert_equal ['--server', '*'], commands[1][:arguments]
  end

  def test_negated_hosts_and_users
    content = <<~SUDOERS
      admin ALL,!SERVERS=(ALL) /usr/bin/su
      user1 web1,!web2=(root,!apache) /usr/bin/cat
      !invalid_user ALL=(ALL) ALL
    SUDOERS

    result = @parser.parse(content)

    # Check negated hosts
    spec1 = result[0]
    assert_equal ['ALL', '!SERVERS'], spec1[:hosts]

    # Check negated users in RunAs
    spec2 = result[1]
    assert_equal ['web1', '!web2'], spec2[:hosts]
    assert_equal ['root'], spec2[:commands][0][:runas][:users]
    assert_includes spec2[:commands][0][:runas][:original_users], '!apache'
  end

  def test_multiline_command_alias
    content = <<~SUDOERS
      Cmnd_Alias SHELLS = /bin/sh, \\
                         /bin/bash, \\
                         /bin/tcsh, \\
                         /bin/zsh
      admin ALL=(ALL) SHELLS
    SUDOERS

    result = @parser.parse(content)

    # Verify alias definition
    alias_entry = result.find { |e| e[:type] == :alias }
    assert_equal 'Cmnd_Alias', alias_entry[:alias_type]
    assert_equal 'SHELLS', alias_entry[:name]
    assert_equal %w[/bin/sh /bin/bash /bin/tcsh /bin/zsh], alias_entry[:members]

    # Verify command resolution
    user_spec = result.find { |e| e[:type] == :user_spec }
    assert_equal %w[/bin/sh /bin/bash /bin/tcsh /bin/zsh], user_spec[:commands][0][:resolved_commands]
  end

  def test_command_paths_with_spaces
    content = <<~SUDOERS
      admin ALL=(ALL) "/usr/local/bin/my script"
    SUDOERS

    result = @parser.parse(content)

    # Command with spaces must be quoted, but quotes removed in parsed result
    assert_equal '/usr/local/bin/my script', result[0][:commands][0][:command]
  end

  def test_command_with_metacharacters
    content = <<~SUDOERS
      # Shell metacharacters must be quoted
      admin ALL=(ALL) "/usr/bin/find" "/var" "-name" "*.log"
      backup ALL=(ALL) "/bin/tar" "-czf" "backup.tar.gz" "/home/*"
    SUDOERS

    result = @parser.parse(content)
    cmd1 = result[0][:commands][0]
    cmd2 = result[1][:commands][0]

    assert_equal '/usr/bin/find', cmd1[:base_command]
    assert_equal ['/var', '-name', '*.log'], cmd1[:arguments]
    assert_equal '/bin/tar', cmd2[:base_command]
    assert_equal ['-czf', 'backup.tar.gz', '/home/*'], cmd2[:arguments]
  end
end
