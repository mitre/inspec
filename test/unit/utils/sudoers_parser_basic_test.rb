require "minitest/autorun"
require "stringio"
require "logger"
require_relative "../../../lib/inspec/utils/sudoers_parser"

class SudoersParserBasicTest < Minitest::Test
  def setup
    @debug_output = StringIO.new
    @logger = Logger.new(@debug_output).tap do |l|
      l.level = ENV["DEBUG"] ? Logger::DEBUG : Logger::INFO
    end
  end

  def test_basic_command_alias_resolution
    parser = SudoersParser.new(nil, @logger)

    content = <<~SUDOERS
      # Define command alias
      Cmnd_Alias NET = /sbin/ifconfig, /sbin/route

      # Use the alias
      admin ALL=(ALL) NET
    SUDOERS

    result = parser.parse(content)

    # Verify command alias was parsed
    alias_entry = result.find { |e| e[:type] == :alias }
    assert_equal "Cmnd_Alias", alias_entry[:alias_type]
    assert_equal "NET", alias_entry[:name]
    assert_equal ["/sbin/ifconfig", "/sbin/route"], alias_entry[:members]

    # Verify user spec with alias was parsed
    user_spec = result.find { |e| e[:type] == :user_spec }
    assert_equal [{ name: "admin", is_group: false, original: "admin" }], user_spec[:users]
    assert_equal ["ALL"], user_spec[:hosts]

    command = user_spec[:commands].first
    assert_equal "NET", command[:command]
    assert_equal ["/sbin/ifconfig", "/sbin/route"], command[:resolved_commands]
  end

  def test_prints_debug_on_failure
    parser = SudoersParser.new(nil, @logger)

    begin
      parser.parse("Invalid content")
    rescue SudoersParser::ParserError => e
      assert_match(/Error|Failed/, @debug_output.string)
    end
  end
end
