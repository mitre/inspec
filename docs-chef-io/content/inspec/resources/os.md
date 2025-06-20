+++
title = "os resource"
draft = false
gh_repo = "inspec"
platform = "os"

[menu]
  [menu.inspec]
    title = "os"
    identifier = "inspec/resources/os/os.md os resource"
    parent = "inspec/resources/os"
+++

Use the `os` Chef InSpec audit resource to test the platform on which the system is running.

## Availability

### Install

{{< readfile file="content/inspec/reusable/md/inspec_installation.md" >}}

### Version

This resource first became available in v1.0.0 of InSpec.

## Syntax

An `os` resource block declares the platform to be tested. The platform may be specified via matcher or control block name. For example, using a matcher:

    describe os.family do
      it { should eq 'platform_family_name' }
    end

- `'platform_family_name'` (a string) is one of `aix`, `bsd`, `darwin`, `debian`, `hpux`, `linux`, `redhat`, `solaris`, `suse`, `unix`, or `windows`

The parameters available to `os` are:

- `:name` - the operating system name, such as `centos`
- `:family` - the operating system family, such as `redhat`
- `:release` - the version of the operating system as a string, such as `7.3.1611`
- `:arch` - the architecture of the operating system, such as `x86_64`
- `:version` - the version of the operating system as a semantic version object, suitable for semantic version comparisons

## Examples

The following examples show how to use this Chef InSpec audit resource.

### Test for RedHat

    describe os.family do
      it { should eq 'redhat' }
    end

### Test for Ubuntu

    describe os.family do
      it { should eq 'debian' }
    end

### Test for Microsoft Windows

    describe os.family do
      it { should eq 'windows' }
    end

### Test the release version as a string

    describe os.release do
      it { should eq '8.10' }
    end

### Test the semantic version

    describe os.version do
      it { should cmp >= '8.10' }
    end

    describe os.version do
      it { should eq '14.7.2' }
    end

### Test the semantic version components

    describe os.version.major do
      it { should eq 14 }
    end

    describe os.version.minor do
      it { should eq 7 }
    end

    describe os.version.patch do
      it { should eq 2 }
    end

    describe os.version.build do
      it { should eq '23H311' }
    end

### Test the params method

    describe os.params do
      its(['name']) { should eq 'ubuntu' }
      its(['family']) { should eq 'debian' }
      its(['release']) { should eq '22.04' }
      its(['arch']) { should eq 'x86_64' }
      its(['version']) { should eq '22.04' }
      its(['major']) { should eq 22 }
      its(['minor']) { should eq 4 }
      its(['patch']) { should eq 0 }
      its(['build']) { should eq nil }
    end

## Matchers

{{< readfile file="content/inspec/reusable/md/inspec_matchers_link.md" >}}

This resource has the following special matchers.

### os.family? Helpers

The `os` audit resource includes a collection of helpers that enable more granular testing of platforms, platform names, architectures, and releases. Use any of the following platform-specific helpers to test for specific platforms:

- `aix?`
- `bsd?` (including Darwin, FreeBSD, NetBSD, and OpenBSD)
- `darwin?`
- `debian?`
- `hpux?`
- `linux?` (including Alpine Linux, Amazon Linux, ArchLinux, CoreOS, Exherbo, Fedora, Gentoo, and Slackware)
- `redhat?` (including CentOS)
- `solaris?` (including Nexenta Core, OmniOS, Open Indiana, Solaris Open, and SmartOS)
- `suse?`
- `unix?`
- `windows?`

For example, to test for Darwin use:

    describe os.bsd? do
       it { should eq true }
    end

To test for Windows use:

    describe os.windows? do
       it { should eq true }
    end

and to test for Redhat use:

    describe os.redhat? do
       it { should eq true }
    end

Use the following helpers to test for operating system names, releases, and architectures:

    describe os.name do
       it { should eq 'foo' }
    end

    describe os.release do
       it { should eq 'foo' }
    end

    describe os.arch do
       it { should eq 'foo' }
    end

### os.family names

Use `os.family` to enable more granular testing of platforms, platform names, architectures, and releases. Use any of the following platform-specific names to test for specific platforms:

- `aix`
- `bsd` For platforms that are part of the Berkeley OS family `darwin`, `freebsd`, `netbsd`, and `openbsd`.
- `debian`
- `hpux`
- `linux`. For platforms that are part of the Linux family `alpine`, `amazon`, `arch`, `coreos`, `exherbo`, `fedora`, `gentoo`, and `slackware`.
- `redhat`. For platforms that are part of the Redhat family `centos`.
- `solaris`. For platforms that are part of the Solaris family `nexentacore`, `omnios`, `openindiana`, `opensolaris`, and `smartos`.
- `suse`
- `unix`
- `windows`

For example, both of the following tests should have the same result:

```ruby
if os.family == 'debian'
  describe port(69) do
    its('processes') { should include 'in.tftpd' }
  end
elsif os.family == 'redhat'
  describe port(69) do
    its('processes') { should include 'xinetd' }
  end
end

if os.debian?
  describe port(69) do
    its('processes') { should include 'in.tftpd' }
  end
elsif os.redhat?
  describe port(69) do
    its('processes') { should include 'xinetd' }
  end
end
```
