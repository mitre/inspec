require "minitest/autorun"
require "stringio"
require "logger"
require_relative "../../../../lib/inspec/utils/sudoers_parser"

module SudoersParserTestHelper
  def setup_parser
    debug_output = StringIO.new
    logger = Logger.new(debug_output).tap do |l|
      l.level = ENV["DEBUG"] ? Logger::DEBUG : Logger::INFO
    end
    [SudoersParser.new(nil, logger), debug_output]
  end
end
