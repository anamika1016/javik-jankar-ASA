namespace :lg_directory do
  desc "Re-derive hierarchy columns from current dedicated LG data"
  task resync: :environment do
    before = LgDirectory::MODELS.to_h { |model| [model.table_name, model.count] }
    LgDirectory.resync!
    LgDirectory::MODELS.each do |model|
      puts format("%-22s %5d -> %5d  (derived mismatches: %d)",
        model.table_name, before[model.table_name], model.count, LgDirectory.derived_column_mismatch_count(model))
    end
  end

  desc "Check derived columns in the authoritative dedicated LG tables"
  task check: :environment do
    mismatched = LgDirectory::MODELS.reject do |model|
      LgDirectory.derived_column_mismatch_count(model).zero?
    end
    if mismatched.empty?
      puts "Dedicated LG hierarchy columns are consistent."
    else
      puts "Out of sync: #{mismatched.map(&:table_name).join(', ')} -- run rake lg_directory:resync"
      exit 1
    end
  end
end
