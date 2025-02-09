module Inspec
  module Utils
    module Sudoers
      module Types
        class UserSpec
          def initialize(users, hosts, commands)
            @users = users
            @hosts = hosts
            @commands = commands
          end

          def to_h
            {
              type: :user_spec,
              users: @users,
              hosts: @hosts,
              commands: @commands
            }
          end
        end
      end
    end
  end
end
