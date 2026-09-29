# Normalizes stored uploads and SQL STRING_AGG values into individual links.
class ModuleUploadPaths
  def self.call(value)
    case value
    when Array
      value.flat_map { |item| call(item) }.uniq
    when Hash
      value.values.flat_map { |item| call(item) }.uniq
    else
      text = value.to_s.strip
      return [] if text.empty? || text == "-" || text == "null"

      if text.start_with?("[", "{", '"')
        begin
          return call(JSON.parse(text))
        rescue JSON::ParserError
          begin
            # STRING_AGG can join multiple JSON arrays with commas.
            return call(JSON.parse("[#{text}]"))
          rescue JSON::ParserError
            return []
          end
        end
      end
      text.split(/,\s*(?=(?:https?:\/\/|\/?uploads\/))/i).filter_map do |path|
        path = path.strip
        next if path.empty? || path == "-"
        next path if path.match?(/\Ahttps?:\/\//i)
        next "/#{path.delete_prefix('/')}" if path.match?(/\A\/?uploads\//)
      end.uniq
    end
  end
end
