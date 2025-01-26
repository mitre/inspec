require_relative '../../spec_helper'
require 'inspec/utils/sudoers_parser'
require 'parslet'
require 'parslet/convenience'

RSpec.describe SudoersParser do
  let(:parser) { described_class.new }

  # Helper method to debug parse failures
  def debug_parse(rule, input)
    puts "\nDebugging parse failure for: '#{input}'"
    puts "Using rule: #{rule}"
    parser.send(rule).parse_with_debug(input)
  rescue Parslet::ParseFailed => e
    puts e.cause.ascii_tree
  end

  # Basic Constructs
  describe 'basic constructs' do
    describe 'comment' do
      it { expect(parser.comment).to parse('# this is a comment') }
      it { expect(parser.comment).to parse('#') }
      it { expect(parser.comment).not_to parse("# multi\nline") }
    end

    describe 'empty_line' do
      it 'parses newline' do
        expect(parser.empty_line).to parse("\n")
      rescue RSpec::Expectations::ExpectationNotMetError
        debug_parse(:empty_line, "\n")
        raise
      end

      it 'parses spaces with newline' do
        expect(parser.empty_line).to parse("   \n")
      rescue RSpec::Expectations::ExpectationNotMetError
        debug_parse(:empty_line, "   \n")
        raise
      end

      it 'parses comment with newline' do
        expect(parser.empty_line).to parse("# comment\n")
      end
    end
  end

  # Alias Rules
  describe 'alias rules' do
    describe 'alias_definition' do
      it { expect(parser.alias_definition).to parse('User_Alias ADMINS = john, mary') }
      it { expect(parser.alias_definition).to parse('User_Alias ADMINS = john, mary;') }
      it { expect(parser.alias_definition).to parse('Cmnd_Alias SERVICES = /usr/bin/systemctl') }
      it { expect(parser.alias_definition).to parse('Host_Alias WEBSERVERS = web1, web2, web3;') }
      it { expect(parser.alias_definition).not_to parse('Invalid_Alias BAD = value') }
    end
  end

  # Default Rules
  describe 'defaults rules' do
    describe 'defaults_entry' do
      it { expect(parser.defaults_entry).to parse('Defaults env_reset') }
      it { expect(parser.defaults_entry).to parse('Defaults@host timestamp_timeout=20') }
      it { expect(parser.defaults_entry).to parse('Defaults:user !requiretty;') }
      it { expect(parser.defaults_entry).to parse('Defaults>command log_output') }
    end
  end

  # User Specifications
  describe 'user specifications' do
    describe 'assignment' do
      it 'parses basic sudo assignment' do
        expect(parser.assignment).to parse('ALL=(ALL) ALL')
      rescue RSpec::Expectations::ExpectationNotMetError
        debug_parse(:assignment, 'ALL=(ALL) ALL')
        raise
      end

      # Uncomment and add debug support to remaining tests
      it 'parses assignment with semicolon' do
        expect(parser.assignment).to parse('ALL=(ALL) ALL;')
      rescue RSpec::Expectations::ExpectationNotMetError
        debug_parse(:assignment, 'ALL=(ALL) ALL;')
        raise
      end

      it 'parses NOPASSWD specification' do
        expect(parser.assignment).to parse('NOPASSWD: ALL')
      rescue RSpec::Expectations::ExpectationNotMetError
        debug_parse(:assignment, 'NOPASSWD: ALL')
        raise
      end

      it 'parses command with runas spec' do
        expect(parser.assignment).to parse('(root) /usr/bin/su;')
      rescue RSpec::Expectations::ExpectationNotMetError
        debug_parse(:assignment, '(root) /usr/bin/su;')
        raise
      end
    end
  end

  describe '#parse' do
    let(:sudoers_content) do
      <<~SUDOERS
        # Sudo configuration
        Defaults env_reset
        User_Alias ADMINS = john, mary
        %wheel ALL=(ALL) ALL
        ADMINS ALL=(root) NOPASSWD: /usr/bin/systemctl
      SUDOERS
    end

    before do
      allow_any_instance_of(Augeas).to receive(:load!)
      # Add stubs for Augeas matches as needed
    end

    it 'parses comments' do
      # Add test
    end

    it 'parses user aliases' do
      # Add test
    end

    it 'parses defaults' do
      # Add test
    end

    it 'parses user specifications' do
      # Add test
    end
  end
end
