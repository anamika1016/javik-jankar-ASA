class SimpleQrCode
  VERSION = 5
  SIZE = 21 + (VERSION - 1) * 4
  DATA_CODEWORDS = 108
  ECC_CODEWORDS = 26
  FORMAT_MASK = 0x5412
  FORMAT_POLY = 0x537
  ALIGNMENT_POSITIONS = [6, 30].freeze
  PAD_BYTES = [0xec, 0x11].freeze

  MASKS = [
    ->(x, y) { (x + y).even? },
    ->(_x, y) { y.even? },
    ->(x, _y) { (x % 3).zero? },
    ->(x, y) { ((x + y) % 3).zero? },
    ->(x, y) { (((y / 2) + (x / 3)) % 2).zero? },
    ->(x, y) { (((x * y) % 2) + ((x * y) % 3)).zero? },
    ->(x, y) { ((((x * y) % 2) + ((x * y) % 3)) % 2).zero? },
    ->(x, y) { ((((x + y) % 2) + ((x * y) % 3)) % 2).zero? }
  ].freeze

  def self.svg(text, size: 280)
    new(text).svg(size: size)
  end

  def initialize(text)
    @text = text.to_s
    @modules = Array.new(SIZE) { Array.new(SIZE, false) }
    @function = Array.new(SIZE) { Array.new(SIZE, false) }
  end

  def svg(size:)
    raise ArgumentError, "QR text is too long." if @text.bytesize > 106

    setup_function_patterns
    data = data_codewords + reed_solomon(data_codewords, ECC_CODEWORDS)
    best_modules = nil
    best_mask = 0
    best_penalty = Float::INFINITY

    MASKS.each_with_index do |_mask, mask_index|
      candidate = deep_copy(@modules)
      draw_codewords(candidate, data, mask_index)
      draw_format_bits(candidate, mask_index)
      penalty = penalty_score(candidate)
      if penalty < best_penalty
        best_penalty = penalty
        best_modules = candidate
        best_mask = mask_index
      end
    end

    @modules = best_modules
    draw_format_bits(@modules, best_mask)
    to_svg(size)
  end

  private

  def data_codewords
    bits = []
    append_bits(bits, 0b0100, 4)
    append_bits(bits, @text.bytesize, 8)
    @text.bytes.each { |byte| append_bits(bits, byte, 8) }
    terminator = [4, (DATA_CODEWORDS * 8) - bits.length].min
    append_bits(bits, 0, terminator)
    append_bits(bits, 0, (8 - bits.length % 8) % 8)

    bytes = bits.each_slice(8).map { |slice| slice.reduce(0) { |sum, bit| (sum << 1) | bit } }
    pad_index = 0
    while bytes.length < DATA_CODEWORDS
      bytes << PAD_BYTES[pad_index % 2]
      pad_index += 1
    end
    bytes.first(DATA_CODEWORDS)
  end

  def append_bits(bits, value, length)
    (length - 1).downto(0) { |i| bits << ((value >> i) & 1) }
  end

  def setup_function_patterns
    draw_finder(0, 0)
    draw_finder(SIZE - 7, 0)
    draw_finder(0, SIZE - 7)
    draw_alignment(30, 30)
    draw_timing_patterns
    set_function(8, (4 * VERSION) + 9, true)
    reserve_format_areas
  end

  def draw_finder(x, y)
    (-1..7).each do |dy|
      (-1..7).each do |dx|
        xx = x + dx
        yy = y + dy
        next unless in_bounds?(xx, yy)

        dark = dx.between?(0, 6) && dy.between?(0, 6) &&
          ([dx - 3, dy - 3].map(&:abs).max != 2)
        set_function(xx, yy, dark)
      end
    end
  end

  def draw_alignment(cx, cy)
    (-2..2).each do |dy|
      (-2..2).each do |dx|
        dark = [dx.abs, dy.abs].max != 1
        set_function(cx + dx, cy + dy, dark)
      end
    end
  end

  def draw_timing_patterns
    (8...(SIZE - 8)).each do |i|
      dark = i.even?
      set_function(6, i, dark)
      set_function(i, 6, dark)
    end
  end

  def reserve_format_areas
    0.upto(8) do |i|
      set_function(8, i, false) unless i == 6
      set_function(i, 8, false) unless i == 6
    end
    0.upto(7) { |i| set_function(SIZE - 1 - i, 8, false) }
    8.upto(14) { |i| set_function(8, SIZE - 15 + i, false) }
  end

  def set_function(x, y, dark)
    return unless in_bounds?(x, y)

    @modules[y][x] = dark
    @function[y][x] = true
  end

  def draw_codewords(matrix, bytes, mask_index)
    bits = bytes.flat_map { |byte| (7).downto(0).map { |i| (byte >> i) & 1 } }
    bit_index = 0
    upward = true
    x = SIZE - 1

    while x > 0
      x -= 1 if x == 6
      rows = upward ? (SIZE - 1).downto(0) : 0.upto(SIZE - 1)
      rows.each do |y|
        [x, x - 1].each do |xx|
          next if @function[y][xx]

          bit = bit_index < bits.length && bits[bit_index] == 1
          bit = !bit if MASKS[mask_index].call(xx, y)
          matrix[y][xx] = bit
          bit_index += 1
        end
      end
      upward = !upward
      x -= 2
    end
  end

  def draw_format_bits(matrix, mask_index)
    bits = format_bits(mask_index)
    0.upto(5) { |i| matrix[i][8] = bit_at(bits, i) }
    matrix[7][8] = bit_at(bits, 6)
    matrix[8][8] = bit_at(bits, 7)
    matrix[8][7] = bit_at(bits, 8)
    9.upto(14) { |i| matrix[8][14 - i] = bit_at(bits, i) }
    0.upto(7) { |i| matrix[8][SIZE - 1 - i] = bit_at(bits, i) }
    8.upto(14) { |i| matrix[SIZE - 15 + i][8] = bit_at(bits, i) }
    matrix[SIZE - 8][8] = true
  end

  def format_bits(mask_index)
    data = (1 << 3) | mask_index
    value = data << 10
    14.downto(10) do |i|
      value ^= FORMAT_POLY << (i - 10) if ((value >> i) & 1) == 1
    end
    ((data << 10) | value) ^ FORMAT_MASK
  end

  def bit_at(value, index)
    ((value >> index) & 1) == 1
  end

  def reed_solomon(data, degree)
    generator = [1]
    degree.times do |i|
      generator = poly_multiply(generator, [1, gf_pow(2, i)])
    end

    result = Array.new(degree, 0)
    data.each do |byte|
      factor = byte ^ result.shift
      result << 0
      generator[1..].each_with_index do |coef, index|
        result[index] ^= gf_multiply(coef, factor)
      end
    end
    result
  end

  def poly_multiply(left, right)
    product = Array.new(left.length + right.length - 1, 0)
    left.each_with_index do |a, i|
      right.each_with_index do |b, j|
        product[i + j] ^= gf_multiply(a, b)
      end
    end
    product
  end

  def gf_pow(value, power)
    result = 1
    power.times { result = gf_multiply(result, value) }
    result
  end

  def gf_multiply(left, right)
    product = 0
    a = left
    b = right
    while b.positive?
      product ^= a if b.odd?
      a <<= 1
      a ^= 0x11d if a >= 0x100
      b >>= 1
    end
    product
  end

  def penalty_score(matrix)
    score = 0
    lines = matrix + matrix.transpose
    lines.each do |line|
      run_color = line.first
      run_length = 0
      line.each do |cell|
        if cell == run_color
          run_length += 1
        else
          score += 3 + (run_length - 5) if run_length >= 5
          run_color = cell
          run_length = 1
        end
      end
      score += 3 + (run_length - 5) if run_length >= 5
    end

    0.upto(SIZE - 2) do |y|
      0.upto(SIZE - 2) do |x|
        score += 3 if matrix[y][x] == matrix[y][x + 1] &&
          matrix[y][x] == matrix[y + 1][x] &&
          matrix[y][x] == matrix[y + 1][x + 1]
      end
    end

    pattern_score(matrix) + pattern_score(matrix.transpose) + score + balance_penalty(matrix)
  end

  def pattern_score(lines)
    lines.sum do |line|
      line.each_cons(11).count do |window|
        bits = window.map { |cell| cell ? 1 : 0 }.join
        bits == "10111010000" || bits == "00001011101"
      end * 40
    end
  end

  def balance_penalty(matrix)
    dark = matrix.flatten.count(true)
    percent = dark * 100 / (SIZE * SIZE)
    ((percent - 50).abs / 5) * 10
  end

  def to_svg(size)
    quiet = 4
    view_size = SIZE + (quiet * 2)
    cell = size.to_f / view_size
    rects = []
    @modules.each_with_index do |row, y|
      row.each_with_index do |dark, x|
        next unless dark

        rects << %(<rect x="#{((x + quiet) * cell).round(3)}" y="#{((y + quiet) * cell).round(3)}" width="#{cell.ceil}" height="#{cell.ceil}"/>)
      end
    end

    <<~SVG
      <svg class="jj-qr-svg" width="#{size}" height="#{size}" viewBox="0 0 #{size} #{size}" role="img" aria-label="Exam QR code" xmlns="http://www.w3.org/2000/svg">
        <rect width="100%" height="100%" fill="#ffffff"/>
        <g fill="#111827">#{rects.join}</g>
      </svg>
    SVG
  end

  def deep_copy(matrix)
    matrix.map(&:dup)
  end

  def in_bounds?(x, y)
    x.between?(0, SIZE - 1) && y.between?(0, SIZE - 1)
  end
end
