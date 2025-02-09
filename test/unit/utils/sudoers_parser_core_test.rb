require "minitest/autorun"
require "stringio"
require "logger"
require_relative "../../../lib/inspec/utils/sudoers_parser"

class SudoersParserCoreTest < Minitest::Test
  def setup
    @debug_output = StringIO.new
    @logger = Logger.new(@debug_output).tap do |l|
      l.level = ENV["DEBUG"] ? Logger::DEBUG : Logger::INFO
    end
    @parser = SudoersParser.new(nil, @logger)
  end

  def test_basic_defaults_parsing
    content = <<~SUDOERS
      Defaults !authenticate
      Defaults !targetpw
      Defaults timestamp_timeout=0
      Defaults env_keep="HOME, MAIL"
    SUDOERS

    result = @parser.parse(content)
    defaults = result.select { |entry| entry[:type] == :defaults }

    assert_equal 4, defaults.length
    assert_equal [{ key: "!authenticate", value: nil, operator: nil }], defaults[0][:values]
    assert_equal [{ key: "env_keep", value: "HOME, MAIL", operator: "=" }], defaults[3][:values]
  end

  def test_basic_user_spec_parsing
    content = <<~SUDOERS
      root    ALL=(ALL:ALL) ALL
      admin   ALL=(ALL)   NOPASSWD: ALL
      %wheel  ALL=(ALL)   ALL
    SUDOERS

    result = @parser.parse(content)
    user_specs = result.select { |entry| entry[:type] == :user_spec }

    assert_equal 3, user_specs.length
    assert_equal [{ name: "root", is_group: false, original: "root" }], user_specs[0][:users]
    assert_equal true, user_specs[1][:commands][0][:tags].include?("NOPASSWD")
    assert_equal true, user_specs[2][:users][0][:is_group]
  end

  def test_basic_alias_parsing
    content = <<~SUDOERS
      Host_Alias SERVERS = server1, server2
      User_Alias ADMINS = admin, wheel
      Cmnd_Alias SOFTWARE = /bin/rpm, /usr/bin/up2date
    SUDOERS

    result = @parser.parse(content)
    aliases = result.select { |entry| entry[:type] == :alias }

    assert_equal 3, aliases.length
    assert_equal "Host_Alias", aliases[0][:alias_type]
    assert_equal %w{server1 server2}, aliases[0][:members]
    assert_equal "SOFTWARE", aliases[2][:name]
  end
end
