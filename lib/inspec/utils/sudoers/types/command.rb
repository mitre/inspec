module Inspec
  module Utils
    module Sudoers
      module Types
        class Command
          def initialize(command, base_command, arguments, tags, runas)
            @command = command
            @base_command = base_command
            @arguments = arguments
            @tags = tags
            @runas = runas
          end

          def to_h
            {
              command: @command,
              base_command: @base_command,
              arguments: @arguments,
              tags: @tags,
              runas: @runas
            }
          end
        end
      end
    end
  end
end
