# Sudoers Parser TODOs

## Command Alias resolution

### In the aliases section

```yaml
{:type=>:alias,
 :alias_type=>"Cmnd_Alias",
 :name=>"LOGGED_COMMANDS",
 :members=>["/usr/bin/passwd", "/usr/bin/mount"]}
```

### In a user spec

```yaml
{:command=>"LOGGED_COMMANDS",
 :base_command=>"LOGGED_COMMANDS", # Should be expanded
 :arguments=>[],
 :tags=>["LOG_INPUT", "LOG_OUTPUT"],
 :runas=>{:users=>["ALL"], :groups=>[]}}
```
