+++
title = "services resource"
draft = false
gh_repo = "inspec"
platform = "os"

[menu]
  [menu.inspec]
    title = "services"
    identifier = "inspec/resources/os/services.md services resource"
    parent = "inspec/resources/os"
+++

Use the `services` Chef InSpec audit resource to list all services on a system and filter them by various properties such as name, type, enabled status, and running status. This resource complements the singular `service` resource by allowing you to query and test multiple services at once.

## Availability

### Install

{{< readfile file="content/inspec/reusable/md/inspec_installation.md" >}}

### Version

This resource first became available in v6.9.0 of InSpec.

## Syntax

A `services` resource block declares filters to select services, and then tests properties of the selected services:

    describe services do
      its('names') { should include 'sshd' }
    end

    describe services.where(enabled: true) do
      its('count') { should be >= 5 }
    end

    describe services.where { running == true && enabled == true } do
      its('names') { should include 'sshd' }
    end

where

- `names`, `descriptions`, `types`, `enabled`, `running`, `installed`, `startmodes`, and `startnames` are valid properties for this resource
- `where(enabled: true)` represents a filter that selects only enabled services
- `where { running == true }` represents a block-style filter

For example:

    describe services.where(type: 'systemd') do
      it { should exist }
    end

or:

    describe services.where { enabled == true && running == false } do
      it { should_not exist }
    end

## Properties

### names

The `names` property returns an array of service names:

    its('names') { should include 'sshd' }

### descriptions

The `descriptions` property returns an array of service descriptions:

    its('descriptions') { should include 'OpenSSH server daemon' }

### types

The `types` property returns an array of service manager types (e.g., 'systemd', 'windows', 'sysv', 'darwin'):

    its('types') { should include 'systemd' }

### enabled

The `enabled` property returns an array of boolean values indicating whether each service is enabled:

    its('enabled') { should include true }

### running

The `running` property returns an array of boolean values indicating whether each service is currently running:

    its('running') { should include true }

### installed

The `installed` property returns an array of boolean values indicating whether each service is installed:

    its('installed') { should_not include false }

### startmodes

The `startmodes` property returns an array of service start modes (Windows only):

    its('startmodes') { should include 'Auto' }

where `'Auto'`, `'Manual'`, and `'Disabled'` are common Windows service start modes.

### startnames

The `startnames` property returns an array of user accounts that services run under:

    its('startnames') { should include 'LocalSystem' }

On Unix systems, this may be `nil` for services that don't specify a user, or contain values like `'root'`, `'www-data'`, etc. On Windows, common values include `'LocalSystem'`, `'LocalService'`, `'NetworkService'`, or domain accounts.

## Filtering

### where

The `where` method allows you to filter services using hash syntax or block syntax:

Hash syntax:

    describe services.where(name: 'sshd') do
      it { should be_enabled }
      it { should be_running }
    end

Block syntax:

    describe services.where { enabled == true && running == false } do
      its('names') { should be_empty }
    end

You can chain multiple `where` filters:

    describe services.where(type: 'systemd').where { enabled == true } do
      its('count') { should be >= 10 }
    end

## Matchers

{{< readfile file="content/inspec/reusable/md/inspec_matchers_link.md" >}}

This resource has the following special matchers.

### exist

The `exist` matcher tests if any services match the filter:

    describe services.where(name: 'sshd') do
      it { should exist }
    end

### enabled?

The `enabled?` matcher tests if any of the filtered services are enabled:

    describe services.where(name: 'sshd') do
      it { should be_enabled }
    end

### running?

The `running?` matcher tests if any of the filtered services are running:

    describe services.where(name: 'sshd') do
      it { should be_running }
    end

### installed?

The `installed?` matcher tests if any of the filtered services are installed:

    describe services.where(name: 'sshd') do
      it { should be_installed }
    end

## Examples

The following examples show how to use this Chef InSpec audit resource.

### List all service names

    describe services do
      its('names') { should include 'sshd' }
    end

### Test that critical services are running and enabled

    critical_services = %w(sshd networking)

    critical_services.each do |service_name|
      describe services.where(name: service_name) do
        it { should exist }
        it { should be_enabled }
        it { should be_running }
      end
    end

### Find all enabled services

    describe services.where(enabled: true) do
      its('count') { should be >= 5 }
    end

### Find services that are enabled but not running

    describe services.where { enabled == true && running == false } do
      it { should_not exist }
    end

### Filter services by type (systemd)

    describe services.where(type: 'systemd') do
      it { should exist }
      its('count') { should be >= 1 }
    end

### Test Windows services with automatic start mode

    describe services.where(startmode: 'Auto') do
      its('names') { should include 'wuauserv' }
    end

### Find all services running as root (Unix)

    describe services.where(startname: 'root') do
      its('names') { should include 'sshd' }
    end

### Ensure no unauthorized services are running

    unauthorized_services = %w(telnet ftp rsh)

    unauthorized_services.each do |service_name|
      describe services.where(name: service_name) do
        it { should_not be_running }
      end
    end

### Count total services on the system

    describe services do
      its('count') { should be >= 10 }
    end

### Test all running services are also enabled

    describe services.where { running == true && enabled == false } do
      it { should_not exist }
    end
