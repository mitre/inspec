require 'parslet'

module Inspec
  module Utils
    module Sudoers
      class SudoersParser < Parslet::Parser
        # Atoms
        rule(:space)      { match('\s').repeat(1) }
        rule(:space?)     { space.maybe }
        rule(:comma)      { str(',') >> space? }

        # Basic elements
        rule(:identifier) { match('[A-Za-z]') >> match('[A-Za-z0-9_]').repeat }
        rule(:path) { str('/') >> match('[^\s,]').repeat }

        # Aliases
        rule(:alias_name) { match('[A-Z]') >> match('[A-Z0-9_]').repeat }
        rule(:alias_type) do
          str('User_Alias') | str('Runas_Alias') |
            str('Host_Alias') | str('Cmnd_Alias')
        end

        # Main rules
        rule(:alias_def) do
          alias_type >> space >> alias_name >> space? >>
            str('=') >> space? >> alias_list
        end

        root(:sudoers)
      end
    end
  end
end
