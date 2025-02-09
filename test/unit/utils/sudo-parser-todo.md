# Sudoers Parser TODOs

## Offical to Ruby Refactor

3. Use official parser as reference:

* Study the official parser's grammar rules
* Map the token types and rules
* Implement a proper state machine
* Add proper error handling and recovery

4. Benefits of this approach:

* Better maintainability through separation of concerns
* Easier testing of individual components
* Better error handling and reporting
* More consistent with the official implementation
* Reduced complexity in each component

5. Next steps:
6. Create the directory structure
7. Move the existing code into appropriate files
8. Update the tests to use the new structure
9. Gradually refactor each component using the official parser as reference
10. Add tests for each component as you refactor

### Refactor Notes

Yes, I can help find it. The official sudo source code is available on GitHub at: <https://github.com/sudo-project/sudo>

The sudoers parser implementation can be found in these key files:

* plugins/sudoers/sudoers.c - Main sudoers parser
* plugins/sudoers/parser.c - Core parsing logic
* plugins/sudoers/gram.y - Grammar definitions (using yacc/bison)
* plugins/sudoers/toke.l - Lexical analyzer (using lex/flex)

Looking at these files could help us better understand:

* How the official parser handles edge cases
* What validation rules are enforced
* How aliases are managed
* The exact grammar rules for the sudoers format

Would you like me to look at any specific aspect of the official parser implementation to help improve our Ruby version?

## Command Alias resolution

### In the aliases section

```yaml
{:type=>:alias,
 :alias_type=>"Cmnd_Alias",
 :name=>"LOGGED_COMMANDS",
 :members=>["/usr/bin/passwd", "/usr/bin/mount"]}
```

### In a user spec

```yaml
{:command=>"LOGGED_COMMANDS",
 :base_command=>"LOGGED_COMMANDS", # Should be expanded
 :arguments=>[],
 :tags=>["LOG_INPUT", "LOG_OUTPUT"],
 :runas=>{:users=>["ALL"], :groups=>[]}}
```

# Build out Tetsting

## Generally Working

1. Basic Entry Types
   * path: test/unit/utils/sudoers_parser/entry_types_test.rb
     * Defaults (:type => :defaults)
     * Aliases (:type => :alias)
     * User Specifications (:type => :user_spec)

2. Alias Parsing:
   * path: test/unit/utils/sudoers_parser/alias_test.rb
     * Host_Alias
     * User_Alias
     * Cmnd_Alias
     * Multiple members in aliases

3. Defaults Parsing:
    * path: test/unit/utils/sudoers_parser/defaults_test.rb
      * Basic defaults without qualifiers
      * Qualified defaults (>, @, :, !)
      * Multiple values in one line
      * Different operators (=, +=, -=)

4. Command Resolution
   * path: test/unit/utils/sudoers_parser/command_test.rb
     * Basic command parsing
     * Command with arguments
     * Command with tags (NOPASSWD, NOEXEC, etc)
     * Command alias resolution

## Needs Work

1. Nested Command Aliases
   * path: test/unit/utils/sudoers_parser/command_alias_test.rb
     * Recursive alias resolution
     * Multiple levels of nesting
     * Circular reference detection

2. Complex Pattern Handling:
   * path: /test/unit/utils/sudoers_parser/pattern_test.rb
     * Wildcards in commands
     * Character classes
     * Escaped characters

3. RunAs Specifications:
   * path: test/unit/utils/sudoers_parser/runas_test.rb
      * User specification
      * Group specification
      * User and group specification
      * Multiple user and group specifications
      * Multiple RunAs users/groups
      * ALL:ALL format
      * Group specifications

## Fill the Gaps

1. Add new test cases to complex_defaults_test.rb
   * Test for nested quotes in values
   * Test for += and -= operators with multiple values
   * Test for multi-line defaults with continuation
2. Add new test cases to commands_test.rb:
   * Test for negated hosts/users
   * Test for multi-line command aliases
   * Test for command paths with spaces
3. Add new edge case tests:
   * Empty quoted strings
   * Multiple escaping levels
   * Invalid escape sequences
   * Mixed qualifier combinations

## Optimizations

The only potential improvement might be to reduce the duplicate lookups for command aliases (we see multiple "Looking up command alias" messages for the same command), but that's an optimization rather than a functional issue.
