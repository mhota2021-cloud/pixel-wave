#画像の読み込み（Windows Imaging Componentをfiddleで呼ぶ。COMの関数表をたどって使う）
require 'fiddle'

module Wic
  extend self

  CLSID_FACTORY = '{CACAF262-9370-4615-A13B-9F5539DA4C0A}'
  IID_FACTORY = '{EC5EC8A9-C395-4314-9C77-54D7A935FF70}'
  #GUID_WICPixelFormat32bppRGBA
  FORMAT_RGBA32 = '{F5C7AD2D-6A8D-43DD-A7A8-A29935261AE9}'
  GENERIC_READ = 0x80000000

  #COMを初期化する（1回だけ）
  def ensure_com
    return if @com_ready
    ole32 = Fiddle.dlopen('ole32.dll')
    fn = Fiddle::Function.new(ole32['CoInitializeEx'], [Fiddle::Types::VOIDP, Fiddle::Types::INT], Fiddle::Types::INT)
    fn.call(nil, 2)
    @com_ready = true
  end

  #文字列のGUIDを16バイトにする（引数sは波括弧付きの文字列）
  def guid_bytes(s)
    ole32 = Fiddle.dlopen('ole32.dll')
    fn = Fiddle::Function.new(ole32['CLSIDFromString'], [Fiddle::Types::VOIDP, Fiddle::Types::VOIDP], Fiddle::Types::INT)
    text = "#{s}\x00".encode('UTF-16LE')
    text_ptr = Fiddle::Pointer.malloc(text.bytesize)
    text_ptr[0, text.bytesize] = text
    buffer = Fiddle::Pointer.malloc(16)
    hr = fn.call(text_ptr, buffer)
    raise "GUIDを作れませんでした：#{s}" if hr < 0
    buffer
  end

  #工場を作る（戻り値はIWICImagingFactoryのポインタ）
  def factory
    ensure_com
    ole32 = Fiddle.dlopen('ole32.dll')
    fn = Fiddle::Function.new(
      ole32['CoCreateInstance'],
      [Fiddle::Types::VOIDP, Fiddle::Types::VOIDP, Fiddle::Types::INT, Fiddle::Types::VOIDP, Fiddle::Types::VOIDP],
      Fiddle::Types::INT
    )
    out = Fiddle::Pointer.malloc(8)
    #WICはDLLの中で動くので、CLSCTX_INPROC_SERVER（1）で作る（4のCLSCTX_LOCAL_SERVERでは失敗する）
    hr = fn.call(guid_bytes(CLSID_FACTORY), nil, 1, guid_bytes(IID_FACTORY), out)
    raise 'WICの工場を作れませんでした' if hr < 0
    out[0, 8].unpack1('Q')
  end

  #COMの関数を呼ぶ（引数objはオブジェクト、引数indexは関数表の番号、引数arg_typesとret_typeは型、引数argsは引数。HRESULTが負なら例外）
  def invoke(obj, index, arg_types, ret_type, *args)
    vtable = Fiddle::Pointer.new(obj)[0, 8].unpack1('Q')
    fn_ptr = Fiddle::Pointer.new(vtable)[index * 8, 8].unpack1('Q')
    fn = Fiddle::Function.new(fn_ptr, [Fiddle::Types::VOIDP, *arg_types], ret_type)
    result = fn.call(obj, *args)
    if ret_type == Fiddle::Types::INT && result.is_a?(Integer) && result < 0
      raise "WICの呼び出しが失敗しました（番号#{index}、HRESULT #{result.to_s(16)}）"
    end
    result
  end

  #COMのオブジェクトを解放する（引数objはオブジェクト）
  def release(obj)
    return if obj.nil? || obj == 0
    invoke(obj, 2, [], Fiddle::Types::INT)
  rescue StandardError
    nil
  end

  #画像の最初のフレームを返す（引数facは工場、引数pathはファイルの場所。戻り値はフレームのポインタ）
  def first_frame(fac, path)
    out = Fiddle::Pointer.malloc(8)
    text = "#{path}\x00".encode('UTF-16LE')
    text_ptr = Fiddle::Pointer.malloc(text.bytesize)
    text_ptr[0, text.bytesize] = text
    invoke(fac, 3, [Fiddle::Types::VOIDP, Fiddle::Types::VOIDP, Fiddle::Types::UINT, Fiddle::Types::INT, Fiddle::Types::VOIDP], Fiddle::Types::INT,
           text_ptr, nil, GENERIC_READ, 1, out)
    decoder = out[0, 8].unpack1('Q')
    begin
      frame_out = Fiddle::Pointer.malloc(8)
      invoke(decoder, 13, [Fiddle::Types::UINT, Fiddle::Types::VOIDP], Fiddle::Types::INT, 0, frame_out)
      frame_out[0, 8].unpack1('Q')
    ensure
      release(decoder)
    end
  end

  #画素を取り出す（引数sourceは変換済みの画像。戻り値は幅と高さとRGBAのバイト列）
  def pixels_from(source)
    w_buf = Fiddle::Pointer.malloc(4)
    h_buf = Fiddle::Pointer.malloc(4)
    invoke(source, 3, [Fiddle::Types::VOIDP, Fiddle::Types::VOIDP], Fiddle::Types::INT, w_buf, h_buf)
    w = w_buf[0, 4].unpack1('L<')
    h = h_buf[0, 4].unpack1('L<')
    stride = w * 4
    buffer = Fiddle::Pointer.malloc(stride * h)
    invoke(source, 7, [Fiddle::Types::VOIDP, Fiddle::Types::UINT, Fiddle::Types::UINT, Fiddle::Types::VOIDP], Fiddle::Types::INT,
           nil, stride, stride * h, buffer)
    [w, h, buffer[0, stride * h]]
  end

  #32ビットRGBAへ変換する（引数facは工場、引数sourceは画像。戻り値は変換器のポインタ）
  def convert_to_rgba(fac, source)
    out = Fiddle::Pointer.malloc(8)
    invoke(fac, 10, [Fiddle::Types::VOIDP], Fiddle::Types::INT, out)
    converter = out[0, 8].unpack1('Q')
    begin
      invoke(converter, 8, [Fiddle::Types::VOIDP, Fiddle::Types::VOIDP, Fiddle::Types::INT, Fiddle::Types::VOIDP, Fiddle::Types::DOUBLE, Fiddle::Types::INT], Fiddle::Types::INT,
             source, guid_bytes(FORMAT_RGBA32), 0, nil, 0.0, 0)
      converter
    rescue StandardError
      release(converter)
      raise
    end
  end

  #画像を読む（引数pathはファイルの場所。戻り値は幅と高さと色の配列で、変換ツールの読み込みと同じ形）
  def decode(path)
    fac = factory
    frame = nil
    converter = nil
    begin
      frame = first_frame(fac, path)
      converter = convert_to_rgba(fac, frame)
      w, h, bytes = pixels_from(converter)
      pixels = Array.new(w * h) do |i|
        o = i * 4
        [bytes.getbyte(o), bytes.getbyte(o + 1), bytes.getbyte(o + 2)]
      end
      [w, h, pixels]
    ensure
      release(converter)
      release(frame)
      release(fac)
    end
  end


  #縮小画像をBGRAのバイト列で返す（引数pathはファイルの場所、引数max_wとmax_hは収める大きさで、縦横比は保つ。StretchDIBitsで描く用）
  def decode_thumb_bgra(path, max_w, max_h)
    fac = factory
    frame = nil
    scaler = nil
    converter = nil
    begin
      frame = first_frame(fac, path)
      w_buf = Fiddle::Pointer.malloc(4)
      h_buf = Fiddle::Pointer.malloc(4)
      invoke(frame, 3, [Fiddle::Types::VOIDP, Fiddle::Types::VOIDP], Fiddle::Types::INT, w_buf, h_buf)
      src_w = w_buf[0, 4].unpack1('L<')
      src_h = h_buf[0, 4].unpack1('L<')
      scale = [max_w.to_f / src_w, max_h.to_f / src_h, 1.0].min
      target_w = [(src_w * scale).round, 1].max
      target_h = [(src_h * scale).round, 1].max
      out = Fiddle::Pointer.malloc(8)
      invoke(fac, 11, [Fiddle::Types::VOIDP], Fiddle::Types::INT, out)
      scaler = out[0, 8].unpack1('Q')
      invoke(scaler, 8, [Fiddle::Types::VOIDP, Fiddle::Types::UINT, Fiddle::Types::UINT, Fiddle::Types::INT], Fiddle::Types::INT,
             frame, target_w, target_h, 3)
      converter = convert_to_rgba(fac, scaler)
      w, h, bytes = pixels_from(converter)
      bgra = bytes.dup
      (w * h).times do |i|
        o = i * 4
        tmp = bgra.getbyte(o)
        bgra.setbyte(o, bgra.getbyte(o + 2))
        bgra.setbyte(o + 2, tmp)
      end
      [w, h, bgra]
    ensure
      release(converter)
      release(scaler)
      release(frame)
      release(fac)
    end
  end
end
