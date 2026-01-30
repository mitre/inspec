# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

InSpec is an open-source infrastructure testing framework written in Ruby. It provides a domain-specific language (DSL) for describing security and compliance rules that can be shared between software engineers, operations, and security engineers.

## Repository Structure

This is a **multi-gem Ruby project**:

- **inspec** - Main framework gem (inspec.gemspec) - includes cloud provider support (AWS, Azure, GCP) and remote transport plugins
- **inspec-core** - Core functionality without cloud/remote features (inspec-core.gemspec)
- **inspec-bin** - Command-line interface (inspec-bin/inspec-bin.gemspec)
- **inspec-core-bin** - Alternative CLI distribution

Key directories:
- `lib/inspec/` - Core InSpec implementation
  - `resources/` - InSpec resource implementations (170+ resources)
  - `plugin/` - Plugin system
  - `reporters/` - Result reporters
  - `formatters/` - Output formatters
  - `fetcher/` - Profile fetchers
- `lib/plugins/` - Built-in plugins (compliance, parallel, init, sign, etc.)
- `test/` - Test suites
  - `unit/` - Unit tests (Minitest with describe/it syntax)
  - `functional/` - Functional/CLI tests
  - `integration/` - Integration tests
  - `fixtures/` - Test fixtures and sample profiles
- `docs-chef-io/` - User-facing documentation published to docs.chef.io
- `dev-docs/` - Internal development documentation
- `examples/` - Example profiles and usage demos

## Development Commands

### Setup
```bash
# Install dependencies
bundle install

# Accept license (required for development)
# This is handled automatically by rake test tasks
```

### Testing
```bash
# Run all tests (unit + functional)
bundle exec rake test

# Run only unit tests
bundle exec rake test:unit

# Run only functional tests
bundle exec rake test:functional

# Run a single test file
bundle exec m test/unit/resources/user_test.rb

# Run a single test by line number
bundle exec m test/unit/resources/user_test.rb -l 123

# Run tests in parallel (faster)
bundle exec rake test:parallel

# Run tests in isolation (most thorough)
bundle exec rake test:isolated
```

### Linting
```bash
# Run RuboCop linting
bundle exec rake test:lint
```

### Local Installation
```bash
# Build and install gems locally
gem build inspec-core.gemspec
gem install inspec-core-*.gem

# Or use rake
bundle exec rake install
```

### Running InSpec from Source
```bash
# Use bundler to run from source
bundle exec inspec help
bundle exec inspec exec test.rb
```

## Architecture and Patterns

### CLI Architecture

CLI is built using Thor framework with options defined in multiple locations:

1. **Base Options** (`lib/inspec/base_cli.rb`) - Shared option groups:
   - `target_options` - Remote connection settings (SSH, WinRM, Docker)
   - `profile_options` - Profile-related settings
   - `exec_options` - Execution configuration
   - `audit_log_options` - Audit logging settings

2. **Global Options** (`lib/inspec/cli.rb`) - Available to all commands:
   - `--log-level`, `--log-location` - Logging
   - `--diagnose` - Diagnostic output
   - `--color` - Output formatting
   - Plugin control flags

3. **Command-Specific Options** - Defined above each command method

4. **Plugin Options** - Defined in `lib/plugins/*/lib/*/cli.rb`

### Resource Development

Resources live in `lib/inspec/resources/` and follow this pattern:

```ruby
require "inspec/resource"

module Inspec::Resources
  class MyResource < Inspec.resource(1)
    name "my_resource"
    supports platform: "unix"

    desc "Description of the resource"
    example "
      describe my_resource do
        it { should exist }
      end
    "

    def exist?
      # Implementation
    end
  end
end
```

### Transport Layer

InSpec uses the Train library for remote connections. Transport options flow:
CLI → `Inspec::Config` → Train → specific transport plugins (train-winrm, train-ssh, etc.)

### Testing Framework

InSpec uses **Minitest** as the primary testing framework with describe/it syntax (not RSpec):

```ruby
require "helper"

describe "Backend" do
  let(:backend) { Inspec::Backend.create(Inspec::Config.mock) }

  it "accepts an Inspec::Config" do
    _(backend.is_a?(Inspec::Backend)).must_equal true
  end

  it "raises an error if no transport backend can be found" do
    err = _ { backend }.must_raise RuntimeError
    _(err.message).must_equal "Can't find transport backend 'mock'."
  end
end
```

Key testing utilities:
- `require "helper"` - Load test setup
- `MockLoader.new.load_resource(resource_name, *args)` - Test resources
- `FunctionalHelper` - Helper for CLI testing
- Minitest expectations: `must_equal`, `must_raise`, `wont_be_nil`, etc.

### Licensing System

InSpec integrates with Chef's licensing system:

- Configuration in `lib/inspec/utils/licensing_config.rb`
- CLI integration in `lib/inspec/base_cli.rb`
- Runner integration in `lib/inspec/runner.rb`
- Shell integration in `lib/inspec/shell.rb`
- License plugin in `lib/plugins/inspec-license/`

Always check entitlements before executing core functionality.

### Ruby Version Compatibility

- **Required**: Ruby >= 3.1.0
- Uses `# frozen_string_literal: true` - be careful with string mutations:
  ```ruby
  # Good - create mutable string
  out = +""
  out << data

  # Bad - frozen string error
  out = ""
  out << data
  ```

### Error Handling

Use InSpec-specific exceptions:
```ruby
begin
  # operation
rescue Inspec::ProfileSignatureRequired
  $stderr.puts exception.message
  Inspec::UI.new.exit(:signature_required)
rescue Inspec::Error
  $stderr.puts exception.message
  exit(1)
end
```

## Common File Locations

- **CLI definitions**: `lib/inspec/base_cli.rb`, `lib/inspec/cli.rb`
- **Main runner**: `lib/inspec/runner.rb`
- **Resources**: `lib/inspec/resources/`
- **Profiles**: `lib/inspec/profile.rb`
- **Configuration**: `lib/inspec/config.rb`
- **Version**: `VERSION` file (auto-managed) and `lib/inspec/version.rb`
- **UI utilities**: `lib/inspec/ui.rb`

## Testing Remote Connections

```bash
# WinRM basic
bundle exec inspec shell -t winrm://user@host --password 'pass' --winrm-transport plaintext

# WinRM with Kerberos
bundle exec inspec shell -t winrm://user@host \
  --winrm-transport kerberos \
  --kerberos-service host \
  --kerberos-realm DOMAIN.COM

# SSH
bundle exec inspec exec test.rb -t ssh://user@hostname -i /path/to/key

# Docker
bundle exec inspec exec test.rb -t docker://container_id

# AWS
inspec exec test.rb -t aws://us-east-2/my-profile

# Azure
inspec exec test.rb -t azure://subscription_id
```

## Version Management

- **VERSION file**: Auto-managed by release process - DO NOT EDIT
- **lib/inspec/version.rb**: Auto-generated - DO NOT EDIT
- Version bumps handled by Expeditor CI/CD automation

## Files to NEVER Modify

- `VERSION` - Managed by release automation
- `CHANGELOG.md` - Auto-generated from PR labels
- `.expeditor/` - CI/CD configuration
- `Gemfile.lock` - Generated file
- Any files marked as auto-generated

## Git Workflow

Always sign commits using the `-s` flag (Developer Certificate of Origin):

```bash
git commit -s -m "Fix authentication bug"
```

## Release Cycle

- Releases approximately weekly (Thursdays)
- Version follows Semantic Versioning (X.Y.Z)
- Distribution formats: Omnibus packages, Docker, Habitat, RubyGems

## Key Development Principles

1. **Read before modifying**: Always read files before suggesting changes
2. **Follow existing patterns**: Match the style and structure of surrounding code
3. **Security first**: Never log passwords, validate inputs, handle timeouts
4. **Test coverage**: Unit tests required for all new functionality
5. **Documentation**: Update `docs-chef-io/` when changing user-facing features
