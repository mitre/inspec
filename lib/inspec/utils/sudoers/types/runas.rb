module Inspec
  module Utils
    module Sudoers
      module Types
        class RunAs
          def initialize(users, groups)
            @users = users
            @groups = groups
          end

          def to_h
            {
              users: @users,
              groups: @groups,
            }
          end
        end
      end
    end
  end
end
