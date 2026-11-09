#ドット絵化の結果のキャッシュ（Marshalで保存し、2回目からは読むだけにする）
require 'fileutils'

module DotCache
  module_function

  #キャッシュのファイル名を作る（引数idは絵の識別子、引数mtimeはファイルの更新日時、引数colsとrowsはドットの数）
  def file_name(id, mtime, cols, rows)
    safe = id.gsub(/[^0-9A-Za-z_-]/, '_')
    "#{safe}_#{mtime.to_i}_#{cols}x#{rows}.marshal"
  end

  #キャッシュを読む（引数dirはキャッシュのフォルダ、他の引数はfile_nameと同じ。無ければnil）
  def read(dir, id, mtime, cols, rows)
    path = File.join(dir, file_name(id, mtime, cols, rows))
    return nil unless File.exist?(path)
    data = Marshal.load(File.binread(path))
    return nil unless data.is_a?(Hash) && data[:palette].is_a?(Array) && data[:indices].is_a?(Array)
    return nil unless data[:indices].length == cols * rows
    data
  rescue StandardError
    nil
  end

  #キャッシュへ書く（引数dirはキャッシュのフォルダ、引数dataはパレットと番号の組）
  def write(dir, id, mtime, cols, rows, data)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, file_name(id, mtime, cols, rows))
    File.binwrite(path, Marshal.dump(data))
  end
end
