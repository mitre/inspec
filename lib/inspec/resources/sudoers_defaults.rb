module Inspec::Resources
  class SudoersDefaults
    filter = FilterTable.create
    filter.register_column(:name, field: :name)
    filter.register_column(:value, field: :value)
    filter.register_column(:type, field: :type)
    filter.register_column(:setting, field: :setting)
    filter.register_column(:user, field: :user)
    filter.register_column(:category, field: :category)
    filter.register_column(:target_type, field: :target_type)
    filter.register_column(:target, field: :target)
    filter.register_column(:binding_type, field: :binding_type)
    filter.register_column(:binding_target, field: :binding_target)
    filter.register_custom_matcher(:include?) do |x, expected|
      x.entries.any? do |e|
        e[:value].to_s.include?(expected.to_s)
      end
    end
    filter.register_column(:values) { |t, _| t.entries.map { |e| e[:value] } }
    filter.register_column(:binding_details) do |t, _|
      t.entries.map do |e|
        { binding_type: e[:binding_type], binding_target: e[:binding_target], setting: e[:setting], value: e[:value] }
      end
    end
    filter.register_custom_matcher(:has_binding_type?) do |x, expected|
      x.entries.any? do |e|
        e[:binding_type] == expected
      end
    end
    filter.install_filter_methods_on_resource(self, :settings)

    attr_reader :settings

    def initialize(settings)
      @settings = transform_settings(settings)
    end

    private

    def transform_settings(settings)
      result = []
      settings.each do |category, values|
        if category == 'Defaults'
          values.each do |key, val|
            if key.include?(':') || key.include?('>') || key.include?('@') || key.include?('!')
              binding_type_symbol = key[0]
              binding_key = key[1..-1].strip
              settings_list = binding_key.split(/\s*,\s*/)
              settings_list.each do |setting_item|
                binding_type, target, setting = extract_binding_details(binding_type_symbol, setting_item)
                next if binding_type.nil? || target.nil?

                result << { name: target, type: binding_type, target_type: binding_type, target:, setting:,
                            value: val.is_a?(Array) ? val.join(',') : val.to_s, binding_type:, binding_target: target }
              end
            else
              key, value = key.split('=', 2).map(&:strip) if key.include?('=')
              result << { name: key, value: value ? value.split(/,\s*/) : [], type: 'global_default' }
            end
          end
        else
          category, spec = category.split('_', 2) if category.include?('_')
          sudo_config_hash = { name: spec, value: values.is_a?(Array) ? values.join(',') : values.to_s, type: 'alias',
                               category: }
          result << sudo_config_hash
        end
      end
      result
    end

    def extract_binding_details(binding_type_symbol, key)
      binding_type = nil
      target = nil
      setting = nil
      case binding_type_symbol
      when ':'
        binding_type = 'user'
        target, setting = key.split('=', 2).map(&:strip) if key.include?('=')
        target ||= key
      when '>'
        binding_type = 'command'
        target, setting = key.split('=', 2).map(&:strip) if key.include?('=')
        target ||= key
      when '@'
        binding_type = 'host'
        target, setting = key.split('=', 2).map(&:strip) if key.include?('=')
        target ||= key
      when '!'
        binding_type = 'negated_command'
        target, setting = key.split('=', 2).map(&:strip) if key.include?('=')
        target ||= key
      end
      [binding_type, target, setting]
    end
  end
end
