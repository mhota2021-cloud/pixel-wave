#設定ファイル（settings.json）の読み書き
require 'json'
require 'fileutils'

module AppSettings
  module_function

  #初期設定を返す（引数builtin_idsは素材の絵のidの一覧）
  def defaults(builtin_ids)
    {
      'enabled' => builtin_ids.dup,
      'userImages' => [],
      'wallpaper' => false,
      'pauseOnBattery' => true,
      'autostart' => true,
      'builtinCrop' => {},
      'hiddenBuiltin' => [],
      'mode' => 'dotart'
    }
  end

  #設定を読む（引数dirはデータフォルダ、引数builtin_idsは素材の絵のidの一覧。読めないときは初期設定で、壊れたファイルは退避する）
  def load(dir, builtin_ids)
    path = File.join(dir, 'settings.json')
    return defaults(builtin_ids) unless File.exist?(path)
    begin
      data = JSON.parse(File.read(path))
      raise '形が違います' unless data.is_a?(Hash) && data['enabled'].is_a?(Array) && data['userImages'].is_a?(Array)
      {
        'enabled' => data['enabled'],
        'userImages' => data['userImages'],
        'wallpaper' => data['wallpaper'] ? true : false,
        'pauseOnBattery' => data.key?('pauseOnBattery') ? (data['pauseOnBattery'] ? true : false) : true,
        'autostart' => data.key?('autostart') ? (data['autostart'] ? true : false) : true,
        'builtinCrop' => data['builtinCrop'].is_a?(Hash) ? data['builtinCrop'] : {},
        'hiddenBuiltin' => data['hiddenBuiltin'].is_a?(Array) ? data['hiddenBuiltin'] : [],
        'mode' => data['mode'] == 'normal' ? 'normal' : 'dotart'
      }
    rescue StandardError
      begin
        FileUtils.mv(path, File.join(dir, 'settings.broken.json'))
      rescue StandardError
        nil
      end
      defaults(builtin_ids)
    end
  end

  #設定を保存する（引数dirはデータフォルダ、引数settingsは設定）
  def save(dir, settings)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'settings.json'), JSON.generate(settings))
  end
end
