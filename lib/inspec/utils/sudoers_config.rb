require 'inspec/utils/sudoers_parser'
require 'inspec/utils/sudoers_transform'

class SudoersConfig
  def self.parse(content)
    lex = SudoersParser.new.parse(content)
    tree = SudoersTransform.new.apply(lex)
    gtree = SudoersTransform::Group.new(nil, '', tree)
    read_sudoers_group(gtree)
  rescue Parslet::ParseFailed => e
    raise "Failed to parse sudoers config: #{e}"
  end

  def self.read_sudoers_group(t)
    agg_conf = Hash.new([])
    agg_conf['_'] = t.args unless t.args == ''

    groups, conf = t.body.partition { |i| i.is_a? SudoersTransform::Group }
    conf.each { |x| agg_conf[x.key] += [x.vals] }
    groups.each { |x| agg_conf[x.id] += [read_sudoers_group(x)] }
    agg_conf
  end
end
