require_relative 'errors'
require_relative 'tokenizer'
require_relative 'validators'
require_relative 'types/alias'
require_relative 'types/defaults'
require_relative 'types/command'
require_relative 'types/runas'
require_relative 'types/user_spec'

module Inspec
  module Utils
    module Sudoers
      class Parser
        def initialize(content = nil, logger = nil)
          @content = content
          @logger = logger || default_logger
          @tokenizer = Tokenizer.new(@logger)
          @validators = Validators.new(@logger)
        end

        def parse(content = nil)
          @content = content if content
          raise ParserError, 'No content provided' unless @content

          tree = SudoersParser.new.parse(@content)
          SudoersTransform.new.apply(tree)
        rescue Parslet::ParseFailed => e
          raise ParserError, "Parse error: #{e.cause.ascii_tree}"
        end

        private

        def parse_tokens(tokens)
          # Parsing logic will go here
        end

        def default_logger
          require 'logger'
          Logger.new($stdout).tap do |l|
            l.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
          end
        end
      end
    end
  end
end
