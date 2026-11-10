# Only pure label comparisons belong here. Nothing is shared between requests,
# and copied keys keep an in-place edit to an input string from corrupting it.
module RequestLabelMatchCache
  private

  def cached_normalized_person_label(value)
    @normalized_person_labels ||= {}
    key = value.to_s
    cached = @normalized_person_labels[key]
    return cached.dup if cached

    @normalized_person_labels.clear if @normalized_person_labels.size >= 4096
    result = yield
    @normalized_person_labels[key] = result.dup.freeze
    result
  end

  def cached_person_label_match(expected, actual)
    @person_label_matches ||= {}
    key = [expected.to_s, actual.to_s]
    return @person_label_matches[key] if @person_label_matches.key?(key)

    # Lists can contain arbitrary imported labels; bound request memory too.
    @person_label_matches.clear if @person_label_matches.size >= 4096
    key = key.map { |value| value.dup.freeze }.freeze
    @person_label_matches[key] = yield
  end
end
