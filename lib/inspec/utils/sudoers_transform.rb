require 'parslet'

class SudoersTransform < Parslet::Transform
  Group = Struct.new(:id, :args, :body)
  Exp = Struct.new(:key, :vals)
  Default = Struct.new(:user, :command, :host, :args)

  rule(section: { identifier: simple(:x) }, args: subtree(:y), expressions: subtree(:z)) do
    Group.new(x.to_s, y || [], z)
  end
  rule(assignment: { identifier: simple(:x), args: subtree(:y) }) { Exp.new(x.to_s, y || []) }
  rule(value: simple(:x)) { x.to_s }
  rule(default: { user: simple(:u), command: simple(:c), host: simple(:h), args: subtree(:a) }) do
    Default.new(u ? u.to_s : nil, c ? c.to_s : nil, h ? h.to_s : nil, a)
  end
end
