# Decide eligibility using small headers before reading serialized farmer lists
# or preloading owners. The final relation keeps its original scope and ordering.
class TargetFormReadQuery
  Header = Struct.new(:id, :main_activity_name, :activity_name)

  def self.filter(scope)
    return scope unless scope.is_a?(ActiveRecord::Relation)

    ids = scope.reorder(nil).pluck(:id, :main_activity_name, :activity_name)
      .filter_map do |attributes|
        header = Header.new(*attributes)
        header.id if yield(header)
      end
    scope.where(id: ids)
  end
end
