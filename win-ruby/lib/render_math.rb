#描画の座標計算（純粋関数。マスの四隅は整数のピクセルにそろえる）
module RenderMath
  module_function

  #ドットの塗る範囲を返す（引数colとrowはドットの位置、引数dotはマスの大きさ、引数fillは塗る大きさ。戻り値はxとyと幅と高さで、すべて整数）
  def dot_rect(col, row, dot, fill)
    inset = (dot - fill) / 2
    [col * dot + inset, row * dot + inset, fill, fill]
  end

  #変わったドット全体を囲む範囲を返す（引数changesは列と行を含む配列、引数dotはマスの大きさ。戻り値はxとyと幅と高さ、無ければnil）
  def union_rect(changes, dot)
    return nil if changes.nil? || changes.empty?
    min_col = changes.map { |c| c[0] }.min
    max_col = changes.map { |c| c[0] }.max
    min_row = changes.map { |c| c[1] }.min
    max_row = changes.map { |c| c[1] }.max
    [min_col * dot, min_row * dot, (max_col - min_col + 1) * dot, (max_row - min_row + 1) * dot]
  end

  #色をCOLORREFの値にする（引数rgbは色。赤が下位バイト）
  def colorref(rgb)
    rgb[0] | (rgb[1] << 8) | (rgb[2] << 16)
  end

  #矩形をピクセル座標の配列にする（引数rectはxとyと幅と高さ。FillRectやDrawTextWへ渡す形）
  def rect_array(rect)
    x, y, w, h = rect
    [x, y, x + w, y + h]
  end
end
