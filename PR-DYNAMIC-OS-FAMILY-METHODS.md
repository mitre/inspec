# PR Implementation Plan: Dynamic OS Family Methods

## Summary

Add dynamic method generation for family check methods (e.g., `os.kubernetes?`, `os.container?`) to the `os` InSpec resource, enabling transport plugins to define custom platform families that are automatically accessible via intuitive helper methods.

## Problem Statement

Currently, the `os` resource in InSpec has a **hardcoded list** of family check methods:

```ruby
# lib/inspec/resources/os.rb, line 24
%w{aix? redhat? debian? suse? bsd? solaris? linux? unix? windows? hpux? darwin?}.each do |os_family|
  define_method(os_family.to_sym) do
    @platform.send(os_family)
  end
end
```

This means:
- Transport plugins (like `train-k8s-container`) can add custom families to `platform.family_hierarchy`
- These families appear correctly in `os.families` output
- But users cannot use intuitive methods like `os.kubernetes?` or `os.container?`
- Users must use the less intuitive `os.families.include?('kubernetes')` instead

## Use Case: Kubernetes Container Transport

The `train-k8s-container` transport plugin connects to containers running in Kubernetes clusters. It:

1. Uses Train's built-in OS detection to identify the actual container OS (ubuntu, alpine, centos, etc.)
2. Adds `kubernetes` and `container` to the family hierarchy

**Current behavior:**
```ruby
inspec> os.families
=> ["debian", "linux", "unix", "os", "kubernetes", "container"]

inspec> os.linux?
=> true

inspec> os.kubernetes?
=> NoMethodError: undefined method `kubernetes?'

inspec> os.families.include?('kubernetes')
=> true  # Works but not intuitive
```

**Desired behavior:**
```ruby
inspec> os.kubernetes?
=> true

inspec> os.container?
=> true
```

## Proposed Solution

Modify the `OSResource` class to dynamically generate family check methods for all families in the platform's hierarchy.

### Implementation

**File:** `lib/inspec/resources/os.rb`

```ruby
require "inspec/resources/platform"

module Inspec::Resources
  class OSResource < PlatformResource
    name "os"
    supports platform: "unix"
    supports platform: "windows"
    desc "Use the os InSpec audit resource to test the platform on which the system is running."
    example <<~EXAMPLE
      describe os[:family] do
        it { should eq 'redhat' }
      end

      describe os.redhat? do
        it { should eq true }
      end

      describe os.linux? do
        it { should eq true }
      end

      # Dynamic family methods (e.g., for Kubernetes containers)
      describe os.kubernetes? do
        it { should eq true }
      end
    EXAMPLE

    # Keep existing hardcoded methods for backwards compatibility and performance
    # These are the "standard" OS families that Train always defines
    %w{aix? redhat? debian? suse? bsd? solaris? linux? unix? windows? hpux? darwin?}.each do |os_family|
      define_method(os_family.to_sym) do
        @platform.send(os_family)
      end
    end

    def initialize
      super
      # Dynamically define family? methods for any additional families
      # in the hierarchy that aren't in the standard list above
      define_dynamic_family_methods
    end

    def resource_id
      @platform.name || "OS"
    end

    def to_s
      "Operating System Detection"
    end

    private

    # Dynamically create family? methods for all families in the hierarchy
    # that don't already have methods defined (from the hardcoded list above)
    def define_dynamic_family_methods
      return unless @platform.respond_to?(:family_hierarchy)

      @platform.family_hierarchy.each do |family_name|
        method_name = "#{family_name}?"

        # Skip if method already exists (from hardcoded list or platform)
        next if respond_to?(method_name)

        # Define the method on this instance
        define_singleton_method(method_name) do
          @platform.family_hierarchy.include?(family_name)
        end
      end
    end
  end
end
```

### Key Design Decisions

1. **Backwards Compatibility**: Keep the existing hardcoded methods - they delegate to `@platform.send(os_family)` which may have special logic

2. **Performance**: Use `define_singleton_method` in `initialize` rather than `method_missing` - methods are defined once per instance, not looked up on every call

3. **No Duplication**: Check `respond_to?` before defining to avoid overwriting existing methods

4. **Instance-level Methods**: Use `define_singleton_method` so each resource instance gets methods appropriate to its platform hierarchy

## Testing Plan

### Unit Tests

**File:** `test/unit/resources/os_test.rb`

Add tests for dynamic family methods:

```ruby
describe "dynamic family methods" do
  # Mock a platform with custom families
  let(:platform_with_k8s) do
    mock_platform = Minitest::Mock.new
    mock_platform.expect(:family_hierarchy, ["debian", "linux", "unix", "os", "kubernetes", "container"])
    mock_platform.expect(:name, "ubuntu")
    mock_platform.expect(:[], "debian", [:family])
    mock_platform
  end

  it "defines kubernetes? method when kubernetes is in family hierarchy" do
    # Setup mock backend with custom platform
    resource = load_resource("os", platform: platform_with_k8s)

    _(resource.kubernetes?).must_equal true
    _(resource.container?).must_equal true
  end

  it "returns false for families not in hierarchy" do
    resource = load_resource("os", platform: platform_with_k8s)

    # windows is not in the hierarchy
    _(resource.windows?).must_equal false
  end

  it "does not override existing hardcoded methods" do
    resource = load_resource("os", platform: platform_with_k8s)

    # linux? should still work via the hardcoded method
    _(resource.linux?).must_equal true
  end
end
```

### Integration Tests

**File:** `test/kitchen/policies/default/controls/os_family_spec.rb`

```ruby
# Test that dynamic family methods work in real scenarios
control "os-dynamic-families" do
  impact 1.0
  title "Dynamic OS family methods"
  desc "Verify that custom platform families create corresponding methods"

  # This test is relevant when running against Kubernetes containers
  # using the train-k8s-container transport
  only_if("Running on Kubernetes") { os.families.include?("kubernetes") }

  describe os do
    it { should respond_to(:kubernetes?) }
    its("kubernetes?") { should eq true }
  end

  describe os do
    it { should respond_to(:container?) }
    its("container?") { should eq true }
  end
end
```

## Files to Modify

1. `lib/inspec/resources/os.rb` - Add dynamic method generation
2. `test/unit/resources/os_test.rb` - Add unit tests
3. `docs-chef-io/content/inspec/resources/os.md` - Update documentation

## Documentation Updates

Add to `docs-chef-io/content/inspec/resources/os.md`:

```markdown
### Dynamic Family Methods

The `os` resource automatically creates helper methods for any platform families
reported by the transport. This is particularly useful for container and cloud
environments where transport plugins may add custom families.

For example, when using the `train-k8s-container` transport to connect to
Kubernetes containers:

```ruby
# Check if running in a Kubernetes container
describe os.kubernetes? do
  it { should eq true }
end

# Check if running in any container
describe os.container? do
  it { should eq true }
end

# Combine with OS checks
describe os do
  it { should be_linux }
  its('kubernetes?') { should eq true }
end
```

Standard family methods (`linux?`, `windows?`, `unix?`, etc.) are always available.
Additional methods are created dynamically based on the platform's family hierarchy.
```

## Migration / Breaking Changes

**None** - This is purely additive:
- Existing hardcoded methods remain unchanged
- New methods are only added, never removed
- No changes to method signatures or return values

## Related Issues / PRs

- Related to `train-k8s-container` plugin which adds `kubernetes` and `container` families
- Benefits any transport plugin that defines custom platform families

## Implementation Steps

1. [ ] Create feature branch from `main`: `git checkout -b feature/dynamic-os-family-methods`
2. [ ] Implement changes to `lib/inspec/resources/os.rb`
3. [ ] Add unit tests to `test/unit/resources/os_test.rb`
4. [ ] Update documentation in `docs-chef-io/content/inspec/resources/os.md`
5. [ ] Run test suite: `bundle exec rake test`
6. [ ] Run linting: `bundle exec chefstyle -a`
7. [ ] Create PR against upstream `inspec/inspec` repository

## Acceptance Criteria

- [ ] `os.kubernetes?` returns `true` when `kubernetes` is in family hierarchy
- [ ] `os.container?` returns `true` when `container` is in family hierarchy
- [ ] Existing `os.linux?`, `os.windows?`, etc. continue to work unchanged
- [ ] No performance regression (methods defined once, not via method_missing)
- [ ] All existing tests pass
- [ ] New unit tests cover dynamic method generation
- [ ] Documentation updated with examples
