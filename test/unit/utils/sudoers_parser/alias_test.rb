require 'minitest/autorun'
require 'stringio'
require 'logger'
require_relative '../../../../lib/inspec/utils/sudoers_parser'

class SudoersParserAliasTest < Minitest::Test
  def setup
    @debug_output = StringIO.new
    @logger = Logger.new(ENV['DEBUG'] ? $stdout : @debug_output).tap do |l|
      l.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::ERROR
      l.formatter = proc do |severity, datetime, _, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
    end

    # Print setup info when in debug mode
    @logger.debug("Setting up test with DEBUG=#{ENV['DEBUG']}")
    @parser = SudoersParser.new(nil, @logger)
  end

  def teardown
    puts @debug_output.string if ENV['DEBUG']
  end

  def test_host_alias_basic
    content = 'Host_Alias WEBSERVERS = www1, www2'
    result = @parser.parse(content)

    assert_equal :alias, result.first[:type]
    assert_equal 'Host_Alias', result.first[:alias_type]
    assert_equal 'WEBSERVERS', result.first[:name]
    assert_equal %w[www1 www2], result.first[:members]
  end

  def test_host_alias_with_ip_addresses
    content = 'Host_Alias NETWORKS = 192.168.0.0/24, 10.0.0.0/8'
    result = @parser.parse(content)

    assert_equal [
      '192.168.0.0/24',
      '10.0.0.0/8'
    ].sort, result.first[:members].sort
  end

  def test_user_alias_basic
    content = 'User_Alias ADMINS = admin1, admin2'
    result = @parser.parse(content)

    assert_equal :alias, result.first[:type]
    assert_equal 'User_Alias', result.first[:alias_type]
    assert_equal 'ADMINS', result.first[:name]
    assert_equal %w[admin1 admin2], result.first[:members]
  end

  def test_user_alias_with_groups
    content = 'User_Alias DBA = %mysql, %postgresql'
    result = @parser.parse(content)

    assert_equal %w[%mysql %postgresql], result.first[:members]
  end

  def test_command_alias_basic
    content = 'Cmnd_Alias SERVICES = /usr/sbin/service, /bin/systemctl'
    result = @parser.parse(content)

    assert_equal :alias, result.first[:type]
    assert_equal 'Cmnd_Alias', result.first[:alias_type]
    assert_equal 'SERVICES', result.first[:name]
    assert_equal %w[/usr/sbin/service /bin/systemctl].sort, result.first[:members].sort
  end

  def test_command_alias_with_arguments
    content = 'Cmnd_Alias DOCKER = /usr/bin/docker pull *, /usr/bin/docker run'
    result = @parser.parse(content)

    assert_equal ['/usr/bin/docker pull *', '/usr/bin/docker run'], result.first[:members]
  end

  def test_multiple_aliases_same_type
    content = <<~SUDOERS
      User_Alias ADMINS = admin1, admin2
      User_Alias DBA = dba1, dba2
    SUDOERS

    result = @parser.parse(content)
    assert_equal 2, result.length
    assert_equal %w[admin1 admin2], result[0][:members]
    assert_equal %w[dba1 dba2], result[1][:members]
    assert_equal %w[User_Alias User_Alias], result.map { |r| r[:alias_type] }
  end

  def test_multiple_alias_types
    content = <<~SUDOERS
      User_Alias ADMINS = admin1, admin2
      Host_Alias WEBSERVERS = web1, web2
      Cmnd_Alias SERVICES = /usr/sbin/service
    SUDOERS

    result = @parser.parse(content)
    assert_equal 3, result.length
    assert_equal %w[User_Alias Host_Alias Cmnd_Alias], result.map { |r| r[:alias_type] }
  end

  def test_alias_with_escaped_characters
    content = 'User_Alias ADMINS = admin\\1, admin\\ 2'
    result = @parser.parse(content)

    assert_equal [
      'admin1',
      'admin 2'
    ].sort, result.first[:members].sort
  end

  def test_alias_with_line_continuation
    content = <<~SUDOERS
      User_Alias ADMINS = admin1, \\
                         admin2, \\
                         admin3
    SUDOERS

    result = @parser.parse(content)
    assert_equal %w[admin1 admin2 admin3], result.first[:members]
  end

  def test_invalid_alias_type
    assert_raises(SudoersParser::ParserError) do
      @parser.parse('Invalid_Alias TESTING = value1')
    end
  end

  def test_invalid_alias_syntax
    [
      'User_Alias',                          # Missing name and members
      'User_Alias ADMINS',                   # Missing equals and members
      'User_Alias = admin1',                 # Missing name
      'User_Alias ADMINS = ',                # Empty members
      'User_Alias ADMINS admin1',            # Missing equals sign
      'User_Alias ADMINS = admin1, = ' # Invalid member list
    ].each do |invalid_content|
      assert_raises(SudoersParser::ParserError, "Should reject: #{invalid_content}") do
        @parser.parse(invalid_content)
      end
    end
  end

  def test_invalid_alias_names
    [
      'User_Alias lower = admin1',           # Lowercase alias name
      'User_Alias 123NUM = admin1',          # Numeric start
      'User_Alias WITH SPACE = admin1',      # Space in name
      'User_Alias WITH@SYMBOL = admin1',     # Special char in name
      'User_Alias ALL = admin1' # Reserved word as name
    ].each do |invalid_content|
      assert_raises(SudoersParser::ParserError, "Should reject: #{invalid_content}") do
        @parser.parse(invalid_content)
      end
    end
  end

  def test_duplicate_alias_names
    content = <<~SUDOERS
      User_Alias ADMINS = admin1
      User_Alias ADMINS = admin2
    SUDOERS

    result = @parser.parse(content)
    admins = result.find { |entry| entry[:name] == 'ADMINS' }
    assert_equal %w[admin1 admin2].sort, admins[:members].sort

    # Test for duplicate removal
    content = <<~SUDOERS
      User_Alias ADMINS = admin1, admin2
      User_Alias ADMINS = admin2, admin3
    SUDOERS

    result = @parser.parse(content)
    admins = result.find { |entry| entry[:type] == :alias && entry[:name] == 'ADMINS' }
    assert_equal %w[admin1 admin2 admin3].sort, admins[:members].sort
  end

  def test_merging_different_alias_types
    content = <<~SUDOERS
      User_Alias ADMINS = admin1
      Host_Alias ADMINS = host1
    SUDOERS

    assert_raises(SudoersParser::ParserError, 'Should reject aliases with same name but different types') do
      @parser.parse(content)
    end
  end

  def test_invalid_alias_members
    [
      'User_Alias ADMINS = @invalid',        # Invalid group syntax
      'Host_Alias HOSTS = 256.256.256.256',  # Invalid IP
      'Host_Alias HOSTS = server:1',         # Invalid hostname
      'Cmnd_Alias CMDS = /invalid/*/path', # Invalid command path
      'User_Alias USERS = user\\ name' # Invalid escaped space
    ].each do |invalid_content|
      assert_raises(SudoersParser::ParserError, "Should reject: #{invalid_content}") do
        @parser.parse(invalid_content)
      end
    end
  end

  def test_cross_alias_type_reference
    content = <<~SUDOERS
      User_Alias ADMINS = admin1
      Host_Alias HOSTS = ADMINS
    SUDOERS

    assert_raises(SudoersParser::ParserError, 'Should reject cross-type alias references') do
      @parser.parse(content)
    end
  end

  def test_tokenization_basic
    content = 'User_Alias ADMINS = admin1, admin2'
    result = @parser.parse(content)

    assert_equal :alias, result.first[:type]
    assert_equal 'User_Alias', result.first[:alias_type]
    assert_equal 'ADMINS', result.first[:name]
    assert_equal %w[admin1 admin2], result.first[:members]
  end

  def test_negated_alias_members
    content = 'User_Alias ADMINS = admin1, !admin2, admin3'
    result = @parser.parse(content)

    assert_equal %w[admin1 !admin2 admin3].sort, result.first[:members].sort
  end

  def test_complex_alias_definition
    content = <<~SUDOERS
      User_Alias COMPLEX = admin1, !admin2, %wheel, %sudo, !%excluded
    SUDOERS

    result = @parser.parse(content)
    assert_equal %w[admin1 !admin2 %wheel %sudo !%excluded].sort, result.first[:members].sort
  end

  def test_alias_tokenization_errors
    [
      'User_Alias = value',           # Missing alias name
      'User_Alias NAME value',        # Missing equals sign
      'User_Alias NAME = !',          # Incomplete negation
      'User_Alias NAME = admin,,dba'  # Empty member
    ].each do |invalid_content|
      assert_raises(SudoersParser::ParserError) do
        @parser.parse(invalid_content)
      end
    end
  end
end
