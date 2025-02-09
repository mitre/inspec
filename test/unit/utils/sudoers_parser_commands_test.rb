require "minitest/autorun"
require "stringio"
require "logger"
require_relative "../../../lib/inspec/utils/sudoers_parser"

class SudoersParserCommandsTest < Minitest::Test
  def setup
    @debug_output = StringIO.new
    @logger = Logger.new(@debug_output).tap do |l|
      l.level = ENV["DEBUG"] ? Logger::DEBUG : Logger::INFO
    end
    @parser = SudoersParser.new(nil, @logger)
  end

  def test_basic_command_parsing
    content = <<~SUDOERS
      admin ALL=(root) /usr/bin/less
    SUDOERS

    result = @parser.parse(content)
    command = result.first[:commands].first

    assert_equal "/usr/bin/less", command[:command]
    assert_equal "/usr/bin/less", command[:base_command]
    assert_equal [], command[:arguments]
    assert_equal [], command[:tags]
  end

  def test_command_with_arguments
    content = <<~SUDOERS
      admin ALL=(root) /usr/bin/kill -9
    SUDOERS

    result = @parser.parse(content)
    command = result.first[:commands].first

    assert_equal "/usr/bin/kill -9", command[:command]
    assert_equal "/usr/bin/kill", command[:base_command]
    assert_equal ["-9"], command[:arguments]
  end

  def test_command_with_pattern
    content = <<~SUDOERS
      admin ALL=(ALL) /usr/bin/passwd [A-Za-z]*
    SUDOERS

    result = @parser.parse(content)
    command = result.first[:commands].first

    assert_equal "/usr/bin/passwd [A-Za-z]*", command[:command]
    assert_equal "/usr/bin/passwd", command[:base_command]
    assert_equal ["[A-Za-z]*"], command[:arguments]
  end

  def test_command_with_tags
    content = <<~SUDOERS
      admin ALL=(root) NOPASSWD:NOEXEC: /usr/bin/less
    SUDOERS

    result = @parser.parse(content)
    command = result.first[:commands].first

    assert_equal "/usr/bin/less", command[:command]
    assert_equal %w{NOPASSWD NOEXEC}, command[:tags]
  end

  def test_command_with_escaped_characters
    content = <<~SUDOERS
      dev_* ALL=(ALL) /usr/bin/\\ls
      admin\\* ALL=(ALL) /usr/bin/id
    SUDOERS

    result = @parser.parse(content)
    commands = result.map { |e| e[:commands].first }

    assert_equal '/usr/bin/\\ls', commands[0][:command]
    assert_equal "/usr/bin/ls", commands[0][:base_command]
    assert_equal "/usr/bin/id", commands[1][:command]
  end

  def test_command_with_multiple_arguments
    content = <<~SUDOERS
      admin ALL=(ALL) /usr/bin/find /var -name "*.log"
    SUDOERS

    result = @parser.parse(content)
    command = result.first[:commands].first

    assert_equal '/usr/bin/find /var -name "*.log"', command[:command]
    assert_equal "/usr/bin/find", command[:base_command]
    assert_equal ["/var", "-name", "*.log"], command[:arguments]
  end

  def test_command_with_quotes
    content = <<~SUDOERS
      admin ALL=(ALL) /bin/echo "Hello World"
      admin ALL=(ALL) /bin/cat '/etc/passwd'
    SUDOERS

    result = @parser.parse(content)
    commands = result.map { |e| e[:commands].first }

    assert_equal ["/bin/echo", "Hello World"], [commands[0][:base_command], commands[0][:arguments].first]
    assert_equal ["/bin/cat", "/etc/passwd"], [commands[1][:base_command], commands[1][:arguments].first]
  end

  def test_command_with_multiple_options
    content = <<~SUDOERS
      admin ALL=(ALL) /usr/bin/vim /[a-z]*/*, /usr/bin/nano /[a-z]*/config
    SUDOERS

    result = @parser.parse(content)
    commands = result.first[:commands]

    assert_equal 2, commands.length
    assert_equal "/usr/bin/vim", commands[0][:base_command]
    assert_equal "/usr/bin/nano", commands[1][:base_command]
    assert_equal ["/[a-z]*/*"], commands[0][:arguments]
    assert_equal ["/[a-z]*/config"], commands[1][:arguments]
  end

  def test_command_with_complex_patterns
    content = <<~SUDOERS
      admin ALL=(ALL) /usr/bin/find "/path with spaces/[0-9]*" -name "*.txt"
      backup ALL=(ALL) /usr/bin/rsync --server *
    SUDOERS

    result = @parser.parse(content)
    commands = result.map { |e| e[:commands].first }

    assert_equal "/usr/bin/find", commands[0][:base_command]
    assert_equal ["/path with spaces/[0-9]*", "-name", "*.txt"], commands[0][:arguments]
    assert_equal "/usr/bin/rsync", commands[1][:base_command]
    assert_equal ["--server", "*"], commands[1][:arguments]
  end
end
