require_relative "errors"

module Inspec
  module Utils
    module Sudoers
      class Tokenizer
        Token = Struct.new(:type, :value, :line_number, :column)

        def initialize(logger = nil)
          @logger = logger
        end

        def tokenize(_input)
          @tokens = []
          @current_line = 1
          @current_column = 1
          # Tokenization logic will go here
          @tokens
        end

        private

        def add_token(type, value)
          @tokens << Token.new(type, value, @current_line, @current_column)
        end
      end
    end
  end
end
