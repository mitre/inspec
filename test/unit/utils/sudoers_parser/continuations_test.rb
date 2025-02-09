require 'minitest/autorun'
require 'stringio'
require 'logger'
require_relative '../../../../lib/inspec/utils/sudoers_parser'

class SudoersParserContinuationsTest < Minitest::Test
  def setup
    @parser = SudoersParser.new
  end

  def test_line_continuation_consistency
    content = <<~SUDOERS
      Defaults env_keep += "DISPLAY \\
          XAUTHORITY"
      Cmnd_Alias SHELLS = /bin/bash, \\
          /bin/sh
      admin ALL = \\
          /usr/bin/su
    SUDOERS

    # Parse multiple times to verify consistency
    results = 5.times.map do
      result = @parser.parse(content)
      result.length
    end

    assert_equal 1, results.uniq.length,
                 "Parser produced inconsistent results across runs: #{results.inspect}"
  end

  def test_spaces_in_continuations
    content = "Defaults env_keep += \"PATH\\ NAME \\
        DISPLAY\""

    result = @parser.parse(content)
    assert_equal 'PATH NAME DISPLAY',
                 result.first[:values].first[:value]
  end
end
