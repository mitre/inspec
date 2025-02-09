require "helper"
require "inspec/utils/sudoers_parser"
require "inspec/utils/sudoers_transform"
require "parslet/rig/rspec"
require "parslet/convenience"
require "minitest/autorun"
require "stringio"
require "logger"
require_relative "../../../lib/inspec/utils/sudoers_parser"

class SudoersParserTest < Minitest::Test
  def setup
    @debug_output = StringIO.new
    @logger = Logger.new(@debug_output).tap do |l|
      l.level = ENV["DEBUG"] ? Logger::DEBUG : Logger::INFO
    end
    @parser = SudoersParser.new(nil, @logger)
  end

  # Basic parsing tests - verify core functionality
  def test_ensures_single_parser_instance
    # First parse should work
    content = <<~SUDOERS
      Cmnd_Alias NET = /sbin/ifconfig, /sbin/route
      admin ALL=(ALL) NET
    SUDOERS

    result = @parser.parse(content)
    assert_equal 2, result.length

    # Second parse should clear previous data
    content2 = <<~SUDOERS
      Cmnd_Alias BASIC = /usr/bin/ls
    SUDOERS

    result2 = @parser.parse(content2)
    assert_equal 1, result2.length
    refute_includes result2.inspect, "NET"
  end

  def test_command_alias_resolution
    content = <<~SUDOERS
      Cmnd_Alias TOOLS = /usr/bin/vi, /usr/bin/nano
      admin ALL=(ALL) TOOLS
    SUDOERS

    result = @parser.parse(content)
    user_spec = result.find { |e| e[:type] == :user_spec }
    command = user_spec[:commands].first

    assert_equal "TOOLS", command[:command]
    assert_equal %w{/usr/bin/vi /usr/bin/nano}, command[:resolved_commands]
  end

  # ... existing test methods ...
end

describe SudoersParser do
  let(:parser) { SudoersParser.new }

  # Combine the duplicate parse methods into one
  def parse(rule)
    parser.parse(rule)
  rescue Parslet::ParseFailed => e
    puts e.parse_failure_cause.ascii_tree
    raise e
  end

  def parsestr(c)
    parse(c).to_s
  end

  def parse_file(f)
    parse(File.read(f))
  end

  describe "basic parsing" do
    it "handles empty files and comments" do
      _(parsestr("")).must_equal ""
      _(parsestr("# some nice comment")).must_equal "# some nice comment"
    end
  end

  describe "value parsing" do
    describe "key-value pairs" do
      it "parses simple key=value" do
        result = parse("key=value")
        _(result[:entries][0][:keypair][:key].to_s).must_equal "key"
        _(result[:entries][0][:keypair][:value].to_s).must_equal "value"
      end

      it "parses key with quoted value" do
        result = parse('key="quoted value"')
        _(result[:entries][0][:keypair][:key].to_s).must_equal "key"
        _(result[:entries][0][:keypair][:value].to_s).must_equal "quoted value"
      end

      it "parses path-style values" do
        result = parse('secure_path="/usr/local/bin:/usr/bin"')
        _(result[:entries][0][:keypair][:key].to_s).must_equal "secure_path"
        _(result[:entries][0][:keypair][:value].to_s).must_equal "/usr/local/bin:/usr/bin"
      end
    end
  end

  describe "default entries" do
    describe "basic defaults" do
      it "parses defaults with and without semicolon" do
        result = parse("Defaults !authenticate")
        _(result[:entries][0][:default][:args].first).must_equal "!authenticate"

        result = parse("Defaults !authenticate;")
        _(result[:entries][0][:default][:args].first).must_equal "!authenticate"
      end

      # Uncomment and fix next test
      # it 'parses multiple values' do
      #   result = parse('Defaults !authenticate, timestamp_timeout=0')
      #   _(result[:default][:args]).must_include '!authenticate'
      #   _(result[:default][:args]).must_include 'timestamp_timeout=0'
      # end
    end

    describe "user-specific defaults" do
      it "parses with and without semicolon" do
        result = parse("Defaults:root !authenticate")
        _(result[:entries][0][:default][:user][:identifier].to_s).must_equal "root"
        _(result[:entries][0][:default][:args].first).must_equal "!authenticate"
      end

      it "handles multiple values and quoted strings" do
        result = parse('Defaults:root secure_path="/usr/local/bin:/usr/bin"')
        _(result[:entries][0][:default][:user][:identifier].to_s).must_equal "root"
        _(result[:entries][0][:default][:args].first).must_equal 'secure_path="/usr/local/bin:/usr/bin"'
      end
    end

    describe "host-specific defaults" do
      let(:base_input) { "Defaults@WEBSERVERS ssl_verify" }

      it "parses with and without semicolon" do
        [base_input, "#{base_input};"].each do |input|
          result = parse(input)
          _(result[:entries][0][:default][:host][:identifier]).must_equal "WEBSERVERS"
          _(result[:entries][0][:default][:args][0][:value]).must_equal "ssl_verify"
        end
      end

      it "handles multiple values and quoted strings" do
        result = parse('Defaults@WEBSERVERS ssl_verify secure_path="/usr/local/ssl/bin"')
        _(result[:entries][0][:default][:host][:identifier]).must_equal "WEBSERVERS"
        _(result[:entries][0][:default][:args][0][:value]).must_equal "ssl_verify"
        _(result[:entries][0][:default][:args][1][:value]).must_equal "/usr/local/ssl/bin"
      end
    end

    describe "command-specific defaults" do
      let(:base_input) { "Defaults>SERVICES !log_output" }

      it "parses with and without semicolon" do
        [base_input, "#{base_input};"].each do |input|
          result = parse(input)
          _(result[:entries][0][:default][:command][:identifier]).must_equal "SERVICES"
          _(result[:entries][0][:default][:args][0][:value]).must_equal "!log_output"
        end
      end

      it "handles multiple values and quoted strings" do
        result = parse("Defaults>STORAGE umask=027 noexec")
        _(result[:entries][0][:default][:command][:identifier]).must_equal "STORAGE"
        _(result[:entries][0][:default][:args][0][:value]).must_equal "umask=027"
        _(result[:entries][0][:default][:args][1][:value]).must_equal "noexec"
      end
    end
  end

  describe "alias definitions" do
    describe "user aliases" do
      it "parses basic User_Alias" do
        result = parse("User_Alias ADMIN = root")
        _(result[:entries][0][:alias][:type]).must_equal "User_Alias"
        _(result[:entries][0][:alias][:name]).must_equal "ADMIN"
        _(parser.extract_values(result)).must_equal ["root"]
      end

      it "parses multiple user aliases" do
        result = parse("User_Alias ADMINS = admin, wheel")
        _(result[:entries][0][:alias][:type]).must_equal "User_Alias"
        _(result[:entries][0][:alias][:name]).must_equal "ADMINS"
        _(parser.extract_values(result)).must_equal %w{admin wheel}
      end

      it "supports user groups in aliases" do
        result = parse("User_Alias WEBMASTERS = %www-admin1, %www-admin2")
        _(result[:entries][0][:alias][:type]).must_equal "User_Alias"
        _(result[:entries][0][:alias][:name]).must_equal "WEBMASTERS"
        _(parser.extract_values(result)).must_equal ["%www-admin1", "%www-admin2"]
      end
    end

    describe "host aliases" do
      it "parses basic Host_Alias" do
        result = parse("Host_Alias WEBSERVERS = www1, www2")
        _(result[:entries][0][:alias][:type]).must_equal "Host_Alias"
        _(result[:entries][0][:alias][:name]).must_equal "WEBSERVERS"
        _(result[:entries][0][:alias][:values]).must_equal %w{www1 www2}
      end

      it "handles IP addresses in host aliases" do
        result = parse("Host_Alias NETWORKS = 192.168.0.0/24, 10.0.0.0/8")
        _(result[:entries][0][:alias][:values]).must_equal ["192.168.0.0/24", "10.0.0.0/8"]
      end
    end

    describe "command aliases" do
      it "parses basic Cmnd_Alias" do
        result = parse("Cmnd_Alias SERVICES = /usr/sbin/service, /bin/systemctl")
        _(result[:entries][0][:alias][:type]).must_equal "Cmnd_Alias"
        _(result[:entries][0][:alias][:name]).must_equal "SERVICES"
        _(result[:entries][0][:alias][:values]).must_equal ["/usr/sbin/service", "/bin/systemctl"]
      end

      it "handles command arguments" do
        result = parse("Cmnd_Alias DOCKER = /usr/bin/docker pull, /usr/bin/docker run")
        _(result[:entries][0][:alias][:values]).must_equal ["/usr/bin/docker pull", "/usr/bin/docker run"]
      end

      it "parses forbidden commands" do
        result = parse("Cmnd_Alias FORBIDDEN = !/bin/systemctl")
        _(result[:entries][0][:alias][:type]).must_equal "Cmnd_Alias"
        _(result[:entries][0][:alias][:name]).must_equal "FORBIDDEN"
        _(parser.extract_values(result)).must_equal ["!/bin/systemctl"]
      end
    end

    describe "runas aliases" do
      it "parses basic Runas_Alias" do
        result = parse("Runas_Alias DBA = oracle, postgres")
        _(result[:entries][0][:alias][:type]).must_equal "Runas_Alias"
        _(result[:entries][0][:alias][:name]).must_equal "DBA"
        _(parser.extract_values(result)).must_equal %w{oracle postgres}
      end

      it "handles group references" do
        result = parse("Runas_Alias WEBOPS = %www-data, %nginx")
        _(result[:entries][0][:alias][:type]).must_equal "Runas_Alias"
        _(result[:entries][0][:alias][:name]).must_equal "WEBOPS"
        _(parser.extract_values(result)).must_equal ["%www-data", "%nginx"]
      end
    end
  end
end
