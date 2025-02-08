require 'minitest/autorun'
require 'stringio'
require 'logger'
require_relative '../../../lib/inspec/utils/sudoers_parser'

class SudoersParserTest < Minitest::Test
  describe 'SudoersParser' do
    # Parse Command Spec Tests
    describe '#parse_command_spec' do
      let(:parser) { SudoersParser.new }

      it 'resolves command aliases' do
        # First parse the full content to populate aliases
        parser.parse(<<~SUDOERS)
          Cmnd_Alias LOGGED_COMMANDS = /usr/bin/passwd, /usr/bin/mount
          admin ALL=(ALL) LOG_INPUT: LOG_OUTPUT: LOGGED_COMMANDS
        SUDOERS

        # Test command alias resolution with tags
        result = parser.send(:parse_command_spec, 'LOG_INPUT: LOG_OUTPUT: LOGGED_COMMANDS', 'ALL')
        assert_equal 'LOGGED_COMMANDS', result[:base_command]
        assert_equal ['/usr/bin/passwd', '/usr/bin/mount'], result[:resolved_commands]
        assert_equal %w[LOG_INPUT LOG_OUTPUT], result[:tags]
      end

      it 'handles tags and non-alias commands' do
        result = parser.send(:parse_command_spec, 'NOPASSWD: NOEXEC: /usr/bin/less', 'ALL')
        assert_equal '/usr/bin/less', result[:base_command]
        assert_nil result[:resolved_commands]
        assert_equal %w[NOPASSWD NOEXEC], result[:tags]
      end
    end

    describe '#parse_quoted_command' do
      let(:parser) { SudoersParser.new }
      let(:null_logger) do
        Logger.new(StringIO.new).tap { |l| l.level = Logger::ERROR }
      end

      it 'handles simple quoted strings' do
        result = parser.send(:parse_quoted_command, '/bin/echo "Hello World"')
        assert_equal ['/bin/echo', 'Hello World'], result
      end

      it 'handles mixed quotes' do
        result = parser.send(:parse_quoted_command, '/bin/echo "Hello \'World\'"')
        assert_equal ['/bin/echo', "Hello 'World'"], result
      end

      it 'handles escaped characters' do
        result = parser.send(:parse_quoted_command, '/bin/echo "Hello\\ World"')
        assert_equal ['/bin/echo', 'Hello World'], result
      end

      it 'handles patterns in quotes' do
        result = parser.send(:parse_quoted_command, '/bin/cat "/var/log/[a-z]*.log"')
        assert_equal ['/bin/cat', '/var/log/[a-z]*.log'], result
      end

      it 'handles complex mixed arguments' do
        cmd = '/usr/bin/find "/path with spaces/[0-9]*" -name "*.txt"'
        result = parser.send(:parse_quoted_command, cmd)
        assert_equal ['/usr/bin/find', '/path with spaces/[0-9]*', '-name', '*.txt'], result
      end

      it 'handles empty quotes and logs warning' do
        log_output = StringIO.new
        custom_logger = Logger.new(log_output)
        parser_with_logger = SudoersParser.new(nil, custom_logger)

        # Test double empty quotes
        result = parser_with_logger.send(:parse_quoted_command, '/usr/bin/echo ""test""')
        assert_equal ['/usr/bin/echo', 'test'], result
        assert_includes log_output.string, 'Found empty quotes in command: /usr/bin/echo ""test""'

        # Reset log output for next test
        log_output.truncate(0)
        log_output.rewind

        # Test single empty quotes
        result = parser_with_logger.send(:parse_quoted_command, "/usr/bin/echo ''value''")
        assert_equal ['/usr/bin/echo', 'value'], result
        assert_includes log_output.string, "Found empty quotes in command: /usr/bin/echo ''value''"
      end

      it 'handles mixed empty quotes' do
        parser_with_null_logger = SudoersParser.new(nil, null_logger)
        result = parser_with_null_logger.send(:parse_quoted_command, '/usr/bin/echo "\'\'test\'\'" \'""value""\'')
        assert_equal ['/usr/bin/echo', "''test''", '""value""'], result
      end
    end

    describe '#pattern_matches?' do
      let(:parser) { SudoersParser.new }

      it 'handles basic patterns' do
        assert parser.send(:pattern_matches?, '/usr/bin/ls', '/usr/bin/ls')
      end

      it 'handles glob patterns' do
        assert parser.send(:pattern_matches?, '/usr/bin/*', '/usr/bin/docker')
      end

      it 'handles character classes' do
        assert parser.send(:pattern_matches?, '/usr/bin/[a-z]*', '/usr/bin/less')
      end

      it 'handles escaped characters' do
        assert parser.send(:pattern_matches?, '/usr/bin/\\[test\\]', '/usr/bin/[test]')
      end
    end
  end
end
