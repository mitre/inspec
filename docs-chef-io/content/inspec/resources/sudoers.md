+++
title = "sudoers resource"
draft = false
gh_repo = "inspec"
platform = "unix"

[menu]
  [menu.inspec]
    title = "sudoers"
    identifier = "inspec/resources/sudoers/sudoers.md"
    parent = "inspec/resources/os"
+++

Use the `sudoers` Chef InSpec audit resource to test sudo configuration on Unix/Linux systems. It parses the content of sudoers files to verify proper sudo settings and access controls.

## Availability

### Install

{{< readfile file="content/inspec/reusable/md/inspec_installation.md" >}}

### Version

This resource first became available in v5.x.x of InSpec.

## Syntax

A `sudoers` resource block declares one or more sudoers files to test:

```ruby
describe sudoers('/etc/sudoers') do
  its('rules') { should_not be_empty }
end

# Test multiple files
describe sudoers('/etc/sudoers /etc/sudoers.d/*') do
  its('settings.Defaults') { should include 'timestamp_timeout' }
end
```

where:

- `rules` returns an array of parsed sudo rules
- `settings` returns a hash of sudo settings and aliases

## Properties

### rules

The `rules` property allows filtering and testing sudo rules using FilterTable:

- `users` - The users/groups the rule applies to
- `hosts` - The hosts where the rule applies
- `run_as` - The user to run the command as
- `tags` - Special tags like NOPASSWD
- `commands` - The commands allowed

### settings

The `settings` property provides access to sudo defaults and aliases:

- `Defaults` - Global and user/host specific defaults
- `Cmnd_Alias` - Command aliases
- `User_Alias` - User aliases
- `Host_Alias` - Host aliases
- `Runas_Alias` - Run-as aliases

### IGNORED_DIRECTIVES

The `IGNORED_DIRECTIVES` property provides a list of directives that are ignored during parsing:

- `#includedir`
- `#include`
- `#includedir /etc/sudoers.d`

## Examples

### Test for NOPASSWD Rules

```ruby
describe sudoers('/etc/sudoers') do
  its('rules.where { !tags.nil? && tags.include?("NOPASSWD:") }.entries') { should be_empty }
end
```

### Verify Required Default Settings

```ruby
describe sudoers('/etc/sudoers') do
  its('settings.Defaults.timestamp_timeout') { should cmp 0 }
  its('settings.Defaults') { should include '!authenticate' }
end
```

### Check for Unrestricted Access

```ruby
describe sudoers('/etc/sudoers /etc/sudoers.d/*') do
  its('rules.where { users == "ALL" && hosts == "ALL" && commands == "ALL" }.entries') { should be_empty }
end
```

### Test User-Specific Rules

```ruby 
describe sudoers('/etc/sudoers') do
  its('rules.where { users == "admin" && commands == "/usr/bin/passwd" }.entries') { should_not be_empty }
end
```

### Test Authentication Settings (SV-258086)

```ruby
describe sudoers('/etc/sudoers') do
  its('settings.Defaults') { should not include '!authenticate' }
end
```

### Test Timeout Settings (SV-258084)

```ruby
describe sudoers('/etc/sudoers') do
  its('settings.Defaults.timestamp_timeout') { should cmp 0 }
end
```

### Test Password Settings (SV-258085)

```ruby
describe sudoers('/etc/sudoers') do
  its('settings.Defaults') { should include ['!targetpw', '!rootpw', '!runaspw'] }
end
```

### Test Privilege Restriction (SV-258087)

```ruby
describe sudoers.rules.where { 
  users == 'ALL' && 
  hosts == 'ALL' && 
  run_as.start_with?('ALL') && 
  commands == 'ALL' 
} do
  it { should be_empty }
end
```

## Matchers

This resource uses special matchers from FilterTable for the `rules` property and standard matchers for the `settings` property.

For a full list of available matchers, please visit our [matchers page](https://docs.chef.io/inspec/matchers/).