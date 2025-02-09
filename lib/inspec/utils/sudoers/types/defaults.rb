module Inspec
  module Utils
    module Sudoers
      module Types
        class Defaults
          def initialize(qualifiers, values)
            @qualifiers = qualifiers
            @values = values
          end

          def to_h
            {
              type: :defaults,
              qualifiers: @qualifiers,
              values: @values
            }
          end
        end
      end
    end
  end
end
