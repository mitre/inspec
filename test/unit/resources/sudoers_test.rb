require "helper"
require "inspec/resource"
require "inspec/resources/sudoers"

describe "Inspec::Resources::Sudoers" do
  describe "properties and interface" do
    resource = load_resource("sudoers")

    it "verifies resource_id is /etc/sudoers by default" do
      _(resource.resource_id).must_equal "/etc/sudoers"
    end

    it "verifies raw_content is loaded" do
      _(resource.raw_content).wont_be_nil
      _(resource.raw_content).must_include "Defaults"
      require "pry"
      binding.pry
    end
  end

  # Test main sudoers file parsing
  describe "Main sudoers file" do
    let(:resource) { load_resource("sudoers", "/etc/sudoers") }

    it "parses complex defaults correctly" do
      defaults = resource.parsed_data.select { |entry| entry[:type] == :defaults }

      # Test environment settings with += operator
      env_keep = defaults.find { |d| d[:values].any? { |v| v[:key] == "env_keep" && v[:operator] == "+=" } }
      _(env_keep[:values].first[:value]).must_include "COLORS"

      # Test quoted values with escaped quotes
      editor = defaults.find { |d| d[:values].any? { |v| v[:key] == "editor" } }
      _(editor[:values].first[:value]).must_include "/usr/bin/vim.basic"
    end

    it "parses complex RunAs specifications" do
      user_specs = resource.parsed_data.select { |entry| entry[:type] == :user_spec }

      admin1_spec = user_specs.find { |spec| spec[:users].any? { |u| u[:name] == "admin1" } }
      _(admin1_spec[:commands].first[:runas][:users]).must_include "operator"
      _(admin1_spec[:commands].first[:runas][:groups]).must_include "wheel"
    end
  end

  # Test included sudoers.d file parsing
  describe "Sudoers.d included file" do
    let(:resource) { load_resource("sudoers", "/etc/sudoers.d/custom") }

    it "parses custom settings" do
      defaults = resource.parsed_data.select { |entry| entry[:type] == :defaults }
      custom_setting = defaults.find { |d| d[:values].any? { |v| v[:key] == "custom_setting" } }
      _(custom_setting[:values].first[:value]).must_equal "value"
    end

    it "parses custom aliases" do
      aliases = resource.parsed_data.select { |entry| entry[:type] == :alias }
      custom_users = aliases.find { |a| a[:name] == "CUSTOM_USERS" }
      _(custom_users[:members]).must_include "custom1"
      _(custom_users[:members]).must_include "custom2"
    end
  end

  # Test combined file loading
  describe "Combined sudoers files" do
    let(:resource) { load_resource("sudoers", ["/etc/sudoers", "/etc/sudoers.d/*"]) }

    it "loads and parses both files" do
      # Test main file content
      _(resource.parsed_data.any? do |entry|
        entry[:type] == :defaults &&
      entry[:values].any? { |v| v[:key] == "secure_path" }
      end).must_equal true

      # Test included file content
      _(resource.parsed_data.any? do |entry|
        entry[:type] == :defaults &&
      entry[:values].any? { |v| v[:key] == "custom_setting" }
      end).must_equal true
    end

    it "combines aliases correctly" do
      aliases = resource.parsed_data.select { |entry| entry[:type] == :alias }

      # Test main file alias
      _(aliases.any? { |a| a[:name] == "SOFTWARE" }).must_equal true

      # Test included file alias
      _(aliases.any? { |a| a[:name] == "CUSTOM_COMMANDS" }).must_equal true
    end
  end
end
