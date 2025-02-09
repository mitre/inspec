module Inspec
  module Utils
    module Sudoers
      module Types
        class Alias
          def initialize(type, name, members)
            @type = type
            @name = name
            @members = members
          end

          def to_h
            {
              type: :alias,
              alias_type: @type,
              name: @name,
              members: @members,
            }
          end
        end
      end
    end
  end
end
