# PR Implementation Plan: Auto-Discover Installed Train Plugins

## Summary

Enhance InSpec's plugin loader to auto-discover `train-*` gems installed via `gem install`, not just those that are direct dependencies of the InSpec gem or registered in `~/.inspec/plugins.json`.

## Problem Statement

Currently, there are THREE ways a plugin can appear in `inspec plugin list`:

| Via | How Discovered | Shows in List |
|-----|----------------|---------------|
| `core` | Bundled in InSpec's lib/plugins directory | Yes |
| `gem (user)` | Registered in `~/.inspec/plugins.json` via `inspec plugin install` | Yes |
| `gem (system)` | Listed as a **direct dependency** of the inspec gem | Yes |

**The problem:** If a user runs `gem install train-k8s-container-mitre`, the plugin:
- **Works** - Train auto-discovers it at runtime when using `-t k8s-container://...`
- **Does NOT show** in `inspec plugin list` - confusing for users

This happens because `detect_system_plugins()` in `lib/inspec/plugin/v2/loader.rb` only scans InSpec's direct dependencies, not all installed gems matching `train-*` or `inspec-*` patterns.

## Root Cause Analysis

**File:** `lib/inspec/plugin/v2/loader.rb`

The `detect_system_plugins` method (lines 354-396):

```ruby
def detect_system_plugins
  # Find the gemspec for inspec
  inspec_gemspec = find_inspec_gemspec("inspec", "=#{Inspec::VERSION}") || ...

  # Make a RequestSet that represents the dependencies of inspec
  inspec_deps_request_set = Gem::RequestSet.new(*inspec_gemspec.dependencies)

  inspec_gemspec.dependencies.each do |inspec_dep|
    next unless inspec_plugin_name?(inspec_dep.name) || train_plugin_name?(inspec_dep.name)
    # Only discovers plugins that are InSpec's direct dependencies
  end
end
```

**What's missing:** A scan for all installed gems matching `train-*` or `inspec-*` patterns.

## Use Case

The `train-k8s-container-mitre` plugin is published to RubyGems. Users can install it via:

```bash
# This works for functionality but plugin doesn't show in list
gem install train-k8s-container-mitre
inspec detect -t k8s-container://default/pod/container  # WORKS
inspec plugin list | grep k8s-container                  # NOT SHOWN

# This works and shows in list
inspec plugin install train-k8s-container-mitre
inspec plugin list | grep k8s-container                  # SHOWN as "gem (user)"
```

Both installation methods should result in the plugin appearing in `inspec plugin list`.

## Proposed Solution

Add a new method `detect_installed_train_plugins` that scans all installed gems for `train-*` patterns, similar to how system plugins are detected but without requiring them to be InSpec dependencies.

### Implementation

**File:** `lib/inspec/plugin/v2/loader.rb`

```ruby
def initialize(options = {})
  @options = options
  @registry = Inspec::Plugin::V2::Registry.instance

  # ... existing code ...

  # Identify plugins that inspec is co-installed with
  detect_system_plugins unless options[:omit_sys_plugins]

  # NEW: Discover any train-* gems installed in the gem path
  # that weren't found as InSpec dependencies
  detect_installed_train_plugins unless options[:omit_sys_plugins]

  # Train plugins are not true InSpec plugins; we need to decorate them
  registry.each do |plugin_name, status|
    fixup_train_plugin_status(status) if train_plugin_name?(plugin_name)
  end
end

private

# Discover train-* gems installed anywhere in the gem path
# These may not be InSpec dependencies but should still be available
def detect_installed_train_plugins
  Gem::Specification.find_all.each do |spec|
    # Only consider train-* plugins
    next unless train_plugin_name?(spec.name)

    # Skip if already registered (from user plugins, system, or core)
    next if registry.key?(spec.name.to_sym)

    status = Inspec::Plugin::V2::Status.new
    status.name = spec.name.to_sym
    status.entry_point = spec.name
    status.version = spec.version.to_s
    status.loaded = false
    status.installation_type = :system_gem
    status.description = spec.summary

    # Train plugins need special handling
    fixup_train_plugin_status(status)

    registry[status.name] = status
  end
end
```

### Key Design Decisions

1. **Runs after `detect_system_plugins`**: Ensures we don't duplicate plugins already found as InSpec dependencies

2. **Uses `Gem::Specification.find_all`**: Scans all installed gems in the gem path, not just InSpec dependencies

3. **Marked as `:system_gem`**: Consistent with how InSpec dependency plugins are marked

4. **Respects existing registry**: Skips plugins already registered via plugins.json or InSpec dependencies

5. **Only train-* plugins**: InSpec plugins (`inspec-*`) installed via `gem install` would need separate consideration (they may have different activation requirements)

## Testing Plan

### Unit Tests

**File:** `test/unit/plugin/v2/loader_test.rb`

```ruby
describe "detect_installed_train_plugins" do
  it "discovers train-* gems not in InSpec dependencies" do
    # Mock a train-* gem that isn't an InSpec dependency
    mock_spec = Gem::Specification.new do |s|
      s.name = "train-k8s-container-mitre"
      s.version = "2.0.1"
      s.summary = "Train transport for K8s containers"
    end

    Gem::Specification.stub :find_all, [mock_spec] do
      loader = Inspec::Plugin::V2::Loader.new

      # Plugin should be discovered
      assert loader.registry.key?(:"train-k8s-container-mitre")

      status = loader.registry[:"train-k8s-container-mitre"]
      assert_equal :system_gem, status.installation_type
      assert_equal :'train-1', status.api_generation
    end
  end

  it "does not duplicate plugins already in registry" do
    # If plugin is in plugins.json, don't add again from gem scan
    # Setup test with plugin in both places
  end
end
```

### Integration Tests

```bash
# Verify gem install results in plugin appearing in list
gem install train-k8s-container-mitre
inspec plugin list | grep k8s-container
# Should show: train-k8s-container-mitre | 2.0.1 | gem (system) | train-1 | ...
```

## Files to Modify

1. `lib/inspec/plugin/v2/loader.rb` - Add `detect_installed_train_plugins` method
2. `test/unit/plugin/v2/loader_test.rb` - Add unit tests
3. `docs-chef-io/content/inspec/plugins.md` - Update plugin installation docs

## Documentation Updates

Add to plugin documentation:

```markdown
### Plugin Discovery

InSpec discovers plugins from multiple sources:

1. **Core plugins** - Bundled with InSpec in `lib/plugins/`
2. **User plugins** - Installed via `inspec plugin install` and tracked in `~/.inspec/plugins.json`
3. **System plugins** - Gems matching `train-*` or `inspec-*` patterns installed in the gem path

All three types appear in `inspec plugin list` output.

**Note:** While both `gem install train-xxx` and `inspec plugin install train-xxx` will make a transport plugin functional, using `inspec plugin install` is recommended as it:
- Tracks the plugin version in `~/.inspec/plugins.json`
- Allows proper uninstallation via `inspec plugin uninstall`
- Manages plugin gem dependencies separately
```

## Migration / Breaking Changes

**None** - This is purely additive:
- Existing plugin discovery mechanisms unchanged
- New plugins discovered that were previously invisible
- No changes to how plugins are loaded or used

## Performance Considerations

`Gem::Specification.find_all` iterates over all installed gems, which could be slow in environments with many gems. However:
- This only runs once during loader initialization
- We bail out early for non-plugin gems
- The scan is O(n) where n is total gems installed

If performance becomes an issue, could optimize with lazy loading or caching.

## Related Issues / PRs

- Discovered while testing `train-k8s-container-mitre` plugin installation
- Benefits any third-party `train-*` plugin published to RubyGems

## Implementation Steps

1. [ ] Create feature branch: `git checkout -b feature/auto-discover-train-plugins`
2. [ ] Implement `detect_installed_train_plugins` in `loader.rb`
3. [ ] Add unit tests
4. [ ] Update documentation
5. [ ] Run test suite: `bundle exec rake test`
6. [ ] Run linting: `bundle exec chefstyle -a`
7. [ ] Create PR against upstream `inspec/inspec` repository

## Acceptance Criteria

- [ ] `gem install train-xxx` results in plugin appearing in `inspec plugin list`
- [ ] Plugin shows as `gem (system)` installation type
- [ ] Plugin shows correct `train-1` API generation
- [ ] Plugins in `~/.inspec/plugins.json` not duplicated
- [ ] InSpec direct dependency plugins not duplicated
- [ ] All existing tests pass
- [ ] New unit tests cover auto-discovery
- [ ] Documentation updated

---

## Related Bug: `plugin list` Crashes for User-Installed Plugins

### Problem

When a plugin is installed via `inspec plugin install` but the gem ends up in the system gem path (not `~/.inspec/gems/`), `inspec plugin list` crashes with:

```
NoMethodError: undefined method `version' for nil
/opt/homebrew/lib/ruby/gems/3.3.0/gems/inspec-core-7.0.95/lib/plugins/inspec-plugin-manager-cli/lib/inspec-plugin-manager-cli/cli_command.rb:516:in `make_pretty_version'
```

This happens with Homebrew-installed cinc-auditor where gems go to `/opt/homebrew/lib/ruby/gems/` instead of `~/.inspec/gems/`.

### Root Cause

**File:** `lib/plugins/inspec-plugin-manager-cli/lib/inspec-plugin-manager-cli/cli_command.rb`

Lines 513-516:

```ruby
Inspec::Plugin::V2::Loader.list_installed_plugin_gems
  .select { |spec| spec.name == plugin_name }
  .max_by(&:version)
  .version  # <-- Crashes because .max_by returns nil when no specs match
```

The issue: `list_installed_plugin_gems` only searches `~/.inspec/gems/`, but the gem may be installed elsewhere.

### Proposed Fix

```ruby
def make_pretty_version(status)
  case status.installation_type
  when :core, :bundle
    Inspec::VERSION
  when :user_gem, :system_gem
    if status.version.nil?
      "(unknown)"
    elsif status.version =~ /^\d+\.\d+\.\d+$/
      status.version
    else
      # Assume it is a version constraint string and try to resolve
      plugin_name = status.name.to_s

      # First try managed gems (InSpec's plugin path)
      spec = Inspec::Plugin::V2::Loader.list_installed_plugin_gems
        .select { |s| s.name == plugin_name }
        .max_by(&:version)

      # Fall back to system gems if not found in managed path
      spec ||= Gem::Specification.find_all_by_name(plugin_name).max_by(&:version)

      spec&.version&.to_s || "(unknown)"
    end
  when :path
    "src"
  end
end
```

### Files to Modify

1. `lib/plugins/inspec-plugin-manager-cli/lib/inspec-plugin-manager-cli/cli_command.rb` - Fix `make_pretty_version`

### Additional Test Case

```ruby
describe "make_pretty_version" do
  it "handles plugins installed in system gem path" do
    # Mock a plugin registered in plugins.json but installed in system gems
    status = Inspec::Plugin::V2::Status.new
    status.name = :"train-k8s-container-mitre"
    status.installation_type = :user_gem
    status.version = "= 2.0.1"  # Version constraint, not exact version

    # Should find version from system gems, not crash
    result = cli.send(:make_pretty_version, status)
    assert_match(/^\d+\.\d+\.\d+$/, result)
  end
end
```

### Acceptance Criteria (Additional)

- [ ] `inspec plugin list` does not crash when plugin gem is in system path
- [ ] Version displays correctly for plugins installed via `inspec plugin install`
- [ ] Falls back to "(unknown)" gracefully if gem cannot be found anywhere
