namespace :farmer_app_logins do
  desc "Fill in village/district/state for farmer logins recorded before place lookup existed"
  task backfill_places: :environment do
    scope = FarmerAppLogin.where(village_name: [nil, ""]).or(
      FarmerAppLogin.where(district_name: [nil, ""])
    )
    puts "#{scope.count} login rows missing a place."

    filled = 0
    scope.find_each do |login|
      lookup = FarmerRegisterLookup.by_mobile(login.mobile_no, refresh: true)
      unless lookup.found?
        puts "  #{login.full_name} (##{login.id}): #{lookup.error}"
        next
      end

      row = Array(lookup.farmer["land_details"]).find { |r| r.is_a?(Hash) && r["village_id"].present? }
      places = AsaLocationNames.for_land_row(row)
      if places.blank?
        puts "  #{login.full_name} (##{login.id}): register has no land row with a village"
        next
      end

      login.update!(
        village_name: login.village_name.presence || places[:village_name],
        block_name: login.block_name.presence || places[:block_name],
        district_name: login.district_name.presence || places[:district_name],
        state_name: login.state_name.presence || places[:state_name]
      )
      filled += 1
      puts "  #{login.full_name} (##{login.id}): #{[places[:village_name], places[:district_name]].compact.join(', ')}"
    end

    puts "Filled #{filled} row(s)."
  end
end
