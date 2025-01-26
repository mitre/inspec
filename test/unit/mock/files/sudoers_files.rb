require 'inspec/backend'

# Mock the file reading for tests
mock = Inspec::Backend.create(Inspec::Config.mock)
mock.mock_command('cat /etc/sudoers', stdout: File.read('test/fixtures/cmd/cat-etc-sudoers'))
mock.mock_command('cat /etc/sudoers.d/custom', stdout: File.read('test/fixtures/cmd/cat-etc-sudoers-d'))
