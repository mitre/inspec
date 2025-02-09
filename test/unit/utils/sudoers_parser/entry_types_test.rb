require "minitest/autorun"
require "stringio"
require "logger"
require_relative "../../../../lib/inspec/utils/sudoers_parser"

class SudoersParserEntryTypesTest < Minitest::Test
  def setup
    @debug_output = StringIO.new
    @logger = Logger.new(@debug_output).tap do |l|
      l.level = Logger::ERROR # Set to ERROR to reduce noise in tests
    end
    @parser = SudoersParser.new(nil, @logger)
  end

  def test_parses_basic_defaults_entry
    content = "Defaults !authenticate, timestamp_timeout=0"
    result = @parser.parse(content)

    assert_equal :defaults, result.first[:type]
    assert_empty result.first[:qualifiers]
    values = result.first[:values]
    assert_equal 2, values.length
    assert_equal({ key: "!authenticate", value: nil, operator: nil }, values[0])
    assert_equal({ key: "timestamp_timeout", value: "0", operator: "=" }, values[1])
  end

  def test_parses_basic_alias_entry
    content = "User_Alias ADMINS = admin1, admin2"
    result = @parser.parse(content)

    assert_equal :alias, result.first[:type]
    assert_equal "User_Alias", result.first[:alias_type]
    assert_equal "ADMINS", result.first[:name]
    assert_equal %w{admin1 admin2}, result.first[:members]
  end

  def test_parses_basic_user_spec_entry
    content = "root ALL=(ALL) ALL"
    result = @parser.parse(content)

    assert_equal :user_spec, result.first[:type]
    assert_equal [{ name: "root", is_group: false, original: "root" }], result.first[:users]
    assert_equal ["ALL"], result.first[:hosts]
    assert_equal "ALL", result.first[:commands].first[:command]
    assert_equal({ users: ["ALL"], groups: [], original_users: ["ALL"], original_groups: [] },
                 result.first[:commands].first[:runas])
  end

  def test_ignores_comments_and_empty_lines
    content = <<~SUDOERS
      # This is a comment

      Defaults env_reset

      # Another comment
      admin ALL=(ALL) ALL
    SUDOERS

    result = @parser.parse(content)
    assert_equal 2, result.length
    assert_equal %i{defaults user_spec}, result.map { |e| e[:type] }
  end

  def test_handles_continuation_lines
    content = <<~SUDOERS
      User_Alias ADMINS = admin1, \\
                         admin2, \\
                         admin3
    SUDOERS

    result = @parser.parse(content)
    assert_equal 1, result.length
    entry = result.first
    assert_equal :alias, entry[:type]
    assert_equal %w{admin1 admin2 admin3}, entry[:members]
  end

  def test_handles_mixed_entry_types
    content = <<~SUDOERS
      Defaults env_reset
      User_Alias ADMINS = admin1
      admin ALL=(ALL) ALL
    SUDOERS

    result = @parser.parse(content)
    assert_equal 3, result.length
    assert_equal %i{defaults alias user_spec}, result.map { |e| e[:type] }
  end

  def test_errors_on_invalid_entries
    assert_raises(SudoersParser::ParserError) do
      @parser.parse("Invalid Entry")
    end
  end
end
