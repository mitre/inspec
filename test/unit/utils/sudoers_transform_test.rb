require 'minitest/autorun'
require 'inspec/utils/sudoers_transform'

class SudoersTransformTest < Minitest::Test
  def setup
    @transform = SudoersTransform.new
  end

  def test_transform_assignment
    result = @transform.apply(assignment: { identifier: 'Defaults', args: { value: '!authenticate' } })
    assert_equal 'Defaults', result.key
    assert_equal '!authenticate', result.vals
  end

  def test_transform_section
    result = @transform.apply(section: { identifier: 'User_Alias' }, args: { value: 'ADMINS = admin, wheel' },
                              expressions: [{ assignment: { identifier: 'Defaults', args: { value: '!authenticate' } } }])
    assert_equal 'User_Alias', result.id
    assert_equal 'ADMINS = admin, wheel', result.args
    assert_equal 'Defaults', result.body.first.key
    assert_equal '!authenticate', result.body.first.vals
  end
end
