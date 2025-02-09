require "minitest/autorun"
require "stringio"
require "logger"
require_relative "../../../../lib/inspec/utils/sudoers_parser"

class SudoersParserEntryCountTest < Minitest::Test
  def setup
    @parser = SudoersParser.new
  end

  def test_entry_counts_are_consistent
    content = File.read(File.join(__dir__, "../../../fixtures/cmd/cat-etc-sudoers"))
    result = @parser.parse(content)

    counts = {
      defaults: result.count { |e| e[:type] == :defaults },
      aliases: result.count { |e| e[:type] == :alias },
      user_specs: result.count { |e| e[:type] == :user_spec },
    }

    # Log the detailed counts
    puts "Entry counts:"
    puts "  Defaults entries: #{counts[:defaults]}"
    puts "  Alias entries: #{counts[:aliases]}"
    puts "  User spec entries: #{counts[:user_specs]}"
    puts "Total entries: #{result.length}"

    # Verify we get the same counts on multiple parses
    5.times do
      new_result = @parser.parse(content)
      assert_equal counts[:defaults], new_result.count { |e| e[:type] == :defaults }
      assert_equal counts[:aliases], new_result.count { |e| e[:type] == :alias }
      assert_equal counts[:user_specs], new_result.count { |e| e[:type] == :user_spec }
      assert_equal result.length, new_result.length
    end
  end
end
