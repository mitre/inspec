require 'minitest/autorun'
require 'stringio'
require 'logger'
require_relative '../../../../lib/inspec/utils/sudoers_parser'

class SudoersParserComplexDefaultsTest < Minitest::Test
  def setup
    @debug_output = StringIO.new
    @logger = Logger.new(@debug_output).tap do |l|
      l.level = Logger::ERROR
    end
    @parser = SudoersParser.new(nil, @logger)
  end

  def test_defaults_with_multiple_qualifiers
    content = 'Defaults:operator>SERVICES !log_output'
    result = @parser.parse(content)

    assert_equal :defaults, result.first[:type]
    qualifiers = result.first[:qualifiers]
    assert_equal 2, qualifiers.length
    assert_equal({ type: ':', target: 'operator' }, qualifiers[0])
    assert_equal({ type: '>', target: 'SERVICES' }, qualifiers[1])
  end

  def test_defaults_with_continued_env_keep
    content = <<~SUDOERS
      Defaults env_keep += "DISPLAY XAUTHORITY XAUTHORIZATION XAPPLRESDIR \\
          XUSERFILESEARCHPATH XFILESEARCHPATH PATH_LOCALE NLSPATH \\
          HOSTALIASES PRINTER LPDEST NETRC"
    SUDOERS

    result = @parser.parse(content)
    assert_equal :defaults, result.first[:type]
    assert_equal '+=', result.first[:values][0][:operator]
  end

  def test_combined_settings_on_one_line
    content = 'Defaults log_year, logfile=/var/log/sudo.log, log_host, loglinelen=0'
    result = @parser.parse(content)

    values = result.first[:values]
    assert_equal 4, values.length
    assert_equal({ key: 'log_year', value: nil, operator: nil }, values[0])
    assert_equal({ key: 'logfile', value: '/var/log/sudo.log', operator: '=' }, values[1])
  end

  def test_env_keep_with_wildcards
    content = 'Defaults env_keep="XDG_*, LANG, LANGUAGE, LINGUAS, LC_*, _XKB_CHARSET"'
    result = @parser.parse(content)

    assert_equal 'env_keep', result.first[:values][0][:key]
    assert_equal 'XDG_*, LANG, LANGUAGE, LINGUAS, LC_*, _XKB_CHARSET', result.first[:values][0][:value]
  end

  def test_nested_quotes_in_values
    content = 'Defaults editor="/usr/bin/vim:\"/usr/bin/vim.basic\""'
    result = @parser.parse(content)

    assert_equal :defaults, result.first[:type]
    assert_equal 'editor', result.first[:values].first[:key]
    assert_equal '/usr/bin/vim:"/usr/bin/vim.basic"', result.first[:values].first[:value]
  end

  def test_multiple_operators_in_defaults
    content = <<~SUDOERS
      Defaults env_keep += "DISPLAY XAUTHORITY"
      Defaults env_keep += "LANG LC_*"
      Defaults env_keep -= "IFS CDPATH"
      Defaults@HOSTS secure_path += "/usr/local/bin", env_keep -= "MAIL"
    SUDOERS

    result = @parser.parse(content)
    defaults = result.select { |entry| entry[:type] == :defaults }

    assert_equal '+=', defaults[0][:values][0][:operator]
    assert_equal 'DISPLAY XAUTHORITY', defaults[0][:values][0][:value]
    assert_equal '+=', defaults[1][:values][0][:operator]
    assert_equal '-=', defaults[2][:values][0][:operator]
    assert_equal 2, defaults[3][:values].length
    assert_equal '+=', defaults[3][:values][0][:operator]
    assert_equal '-=', defaults[3][:values][1][:operator]
  end

  def test_multiline_defaults_with_continuation
    content = <<~SUDOERS
      Defaults    secure_path="/usr/local/sbin:/usr/local/bin:\\
                              /usr/sbin:/usr/bin:/sbin:/bin"
      Defaults    env_keep += "COLORS DISPLAY HOSTNAME \\
                              HISTSIZE INPUTRC KDEDIR \\
                              LESSSECURE LESS_TERMCAP_* \\
                              MAIL PS1 PS2"
    SUDOERS

    result = @parser.parse(content)
    defaults = result.select { |entry| entry[:type] == :defaults }

    expected_path = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    expected_env = 'COLORS DISPLAY HOSTNAME HISTSIZE INPUTRC KDEDIR LESSSECURE LESS_TERMCAP_* MAIL PS1 PS2'

    assert_equal expected_path, defaults[0][:values][0][:value]
    assert_equal expected_env, defaults[1][:values][0][:value]
    assert_equal '+=', defaults[1][:values][0][:operator]
  end
end
