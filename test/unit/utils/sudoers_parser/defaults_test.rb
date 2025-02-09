require "minitest/autorun"
require "stringio"
require "logger"
require_relative "../../../../lib/inspec/utils/sudoers_parser"

class SudoersParserDefaultsTest < Minitest::Test
  def setup
    @debug_output = StringIO.new
    @logger = Logger.new(@debug_output).tap do |l|
      l.level = Logger::ERROR
    end
    @parser = SudoersParser.new(nil, @logger)
  end

  def test_basic_defaults
    content = "Defaults !authenticate, timestamp_timeout=0"
    result = @parser.parse(content)

    assert_equal :defaults, result.first[:type]
    assert_empty result.first[:qualifiers]
    values = result.first[:values]
    assert_equal 2, values.length
    assert_equal({ key: "!authenticate", value: nil, operator: nil }, values[0])
    assert_equal({ key: "timestamp_timeout", value: "0", operator: "=" }, values[1])
  end

  def test_command_specific_defaults
    content = "Defaults>STORAGE umask=027"
    result = @parser.parse(content)

    assert_equal :defaults, result.first[:type]
    assert_equal 1, result.first[:qualifiers].length
    assert_equal({ type: ">", target: "STORAGE" }, result.first[:qualifiers].first)
    assert_equal [{ key: "umask", value: "027", operator: "=" }], result.first[:values]
  end

  def test_host_specific_defaults
    content = "Defaults@WEBSERVERS ssl_verify"
    result = @parser.parse(content)

    assert_equal :defaults, result.first[:type]
    assert_equal 1, result.first[:qualifiers].length
    assert_equal({ type: "@", target: "WEBSERVERS" }, result.first[:qualifiers].first)
    assert_equal [{ key: "ssl_verify", value: nil, operator: nil }], result.first[:values]
  end

  def test_user_specific_defaults
    content = "Defaults:operator !log_output"
    result = @parser.parse(content)

    assert_equal :defaults, result.first[:type]
    assert_equal 1, result.first[:qualifiers].length
    qualifier = result.first[:qualifiers].first
    assert_equal ":", qualifier[:type]
    assert_equal "operator", qualifier[:target]
  end

  def test_negative_user_defaults
    content = "Defaults!PAGERS noexec"
    result = @parser.parse(content)

    assert_equal :defaults, result.first[:type]
    assert_equal 1, result.first[:qualifiers].length
    assert_equal({ type: "!", target: "PAGERS" }, result.first[:qualifiers].first)
    assert_equal [{ key: "noexec", value: nil, operator: nil }], result.first[:values]
  end

  def test_complex_defaults
    content = <<~SUDOERS
      Defaults env_keep="HOME, MAIL"
      Defaults>STORAGE umask=027
      Defaults@WEBSERVERS ssl_verify
      Defaults:operator !log_output
      Defaults!PAGERS noexec
    SUDOERS

    result = @parser.parse(content)
    defaults = result.select { |entry| entry[:type] == :defaults }

    assert_equal 5, defaults.length
    assert_empty defaults[0][:qualifiers]
    assert_equal ">", defaults[1][:qualifiers].first[:type]
    assert_equal "@", defaults[2][:qualifiers].first[:type]
    assert_equal ":", defaults[3][:qualifiers].first[:type]
    assert_equal "!", defaults[4][:qualifiers].first[:type]
  end

  def test_defaults_with_operators
    content = <<~SUDOERS
      Defaults env_keep += "DISPLAY XAUTHORITY"
      Defaults env_keep -= "MAIL"
      Defaults secure_path = "/usr/local/sbin:/usr/local/bin"
    SUDOERS

    result = @parser.parse(content)
    defaults = result.select { |entry| entry[:type] == :defaults }

    assert_equal 3, defaults.length
    assert_equal "+=", defaults[0][:values][0][:operator]
    assert_equal "-=", defaults[1][:values][0][:operator]
    assert_equal "=", defaults[2][:values][0][:operator]
  end
end
