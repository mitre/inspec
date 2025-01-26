require 'minitest/autorun'
require 'inspec/utils/sudoers_config'

class SudoersConfigTest < Minitest::Test
  def test_parse_content
    content = <<~EOF
      Defaults !authenticate
      User_Alias ADMINS = admin, wheel
      Cmnd_Alias SOFTWARE = /bin/rpm, /usr/bin/up2date
    EOF

    result = SudoersConfig.parse(content)
    assert_equal ['!authenticate'], result['Defaults']
    assert_equal ['admin, wheel'], result['User_Alias']['ADMINS']
    assert_equal ['/bin/rpm, /usr/bin/up2date'], result['Cmnd_Alias']['SOFTWARE']
  end

  def test_read_sudoers_group
    group = SudoersTransform::Group.new('Defaults', '!authenticate',
                                        [SudoersTransform::Exp.new('Defaults', '!authenticate')])
    result = SudoersConfig.read_sudoers_group(group)
    assert_equal ['!authenticate'], result['Defaults']
  end
end
