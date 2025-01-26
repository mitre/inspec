require 'helper'
require 'inspec/utils/sudoers_parser'
require 'inspec/utils/sudoers_transform'
require 'parslet/rig/rspec'
require 'parslet/convenience'

describe 'SudoersParser Debug' do
  def debug_parse(str, rule = nil)
    parser = SudoersParser.new
    begin
      result = rule ? parser.send(rule).parse(str) : parser.parse(str)
      puts "\nSuccessful parse of: #{str.inspect}"
      puts "Using rule: #{rule || 'root'}"
      puts 'Result:'
      pp result
      result
    rescue Parslet::ParseFailed => e
      puts "\nParse failed for: #{str.inspect}"
      puts "Using rule: #{rule || 'root'}"
      puts e.parse_failure_cause.ascii_tree if e.parse_failure_cause
      raise
    end
  end

  # Add a helper method to normalize :values to an array
  def extract_values(result)
    values = result[:alias][:values]
    if values.is_a?(Array)
      values.map do |v|
        prefix = v[:prefix] ? v[:prefix].to_s : ''
        open_paren = v[:open_paren] ? '(' : ''
        close_paren = v[:close_paren] ? ')' : ''
        "#{prefix}#{open_paren}#{v[:value]}#{close_paren}"
      end
    elsif values.is_a?(Hash) && values[:value]
      prefix = values[:prefix] ? values[:prefix].to_s : ''
      open_paren = values[:open_paren] ? '(' : ''
      close_paren = values[:close_paren] ? ')' : ''
      ["#{prefix}#{open_paren}#{values[:value]}#{close_paren}"]
    else
      []
    end
  end

  describe 'alias definitions' do
    describe 'User_Alias' do
      it 'parses single value' do
        debug_parse('User_Alias ADMIN = root', :alias_definition)
      end

      it 'parses multiple values' do
        debug_parse('User_Alias ADMINS = admin, wheel', :alias_definition)
      end

      it 'parses group references' do
        debug_parse('User_Alias WEBMASTERS = %www-admin1, %www-admin2', :alias_definition)
      end
    end

    describe 'Host_Alias' do
      it 'parses hostname list' do
        debug_parse('Host_Alias WEBSERVERS = www1, www2', :alias_definition)
      end

      it 'parses network addresses' do
        debug_parse('Host_Alias NETWORKS = 192.168.0.0/24, localhost', :alias_definition)
      end
    end

    describe 'Cmnd_Alias' do
      it 'parses command paths' do
        result = debug_parse('Cmnd_Alias SERVICES = /usr/sbin/service, /bin/systemctl', :alias_definition)
        _(result[:alias][:type]).must_equal 'Cmnd_Alias'
        _(result[:alias][:name]).must_equal 'SERVICES'
        _(extract_values(result)).must_equal ['/usr/sbin/service', '/bin/systemctl']
      end

      it 'parses command paths with arguments' do
        result = debug_parse('Cmnd_Alias DOCKER = /usr/bin/docker *, /usr/bin/docker pull *', :alias_definition)
        _(result[:alias][:type]).must_equal 'Cmnd_Alias'
        _(result[:alias][:name]).must_equal 'DOCKER'
        _(extract_values(result)).must_equal ['/usr/bin/docker *', '/usr/bin/docker pull *']
      end

      it 'parses forbidden commands' do
        result = debug_parse('Cmnd_Alias FORBIDDEN = !/bin/systemctl', :alias_definition)
        _(result[:alias][:type]).must_equal 'Cmnd_Alias'
        _(result[:alias][:name]).must_equal 'FORBIDDEN'
        _(extract_values(result)).must_equal ['!/bin/systemctl']
      end

      it 'parses grouped commands with parentheses' do
        result = debug_parse('Cmnd_Alias GROUPED = (/bin/true, /bin/false)', :alias_definition)
        _(result[:alias][:type]).must_equal 'Cmnd_Alias'
        _(result[:alias][:name]).must_equal 'GROUPED'
        _(extract_values(result)).must_equal ['/bin/true', '/bin/false']
      end

      it 'parses mixed forbidden and grouped commands' do
        result = debug_parse('Cmnd_Alias MIXED = !/bin/systemctl, (/bin/true, /bin/false)', :alias_definition)
        _(result[:alias][:type]).must_equal 'Cmnd_Alias'
        _(result[:alias][:name]).must_equal 'MIXED'
        _(extract_values(result)).must_equal ['!/bin/systemctl', '/bin/true', '/bin/false']
      end
    end

    describe 'Runas_Alias' do
      it 'parses user list' do
        debug_parse('Runas_Alias DBA = oracle, postgres', :alias_definition)
      end

      it 'parses groups' do
        debug_parse('Runas_Alias WEBOPS = %www-data, %nginx', :alias_definition)
      end
    end
  end
end
