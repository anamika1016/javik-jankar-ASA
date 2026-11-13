namespace :farmer_app_logins do
  desc "Fill in village/district/state for farmer logins recorded before place lookup existed"
  task backfill_places: :environment do
    # state_id matters most: it is what decides whose news and videos a
    # farmer receives, and a row without it only ever gets All States posts.
    scope = FarmerAppLogin.where(state_id: [nil, ""])
      .or(FarmerAppLogin.where(village_name: [nil, ""]))
      .or(FarmerAppLogin.where(district_name: [nil, ""]))
    puts "#{scope.count} login rows missing a place or a state."

    filled = 0
    scope.find_each do |login|
      lookup = FarmerRegisterLookup.by_mobile(login.mobile_no, refresh: true)
      unless lookup.found?
        puts "  #{login.full_name} (##{login.id}): #{lookup.error}"
        next
      end

      rows = Array(lookup.farmer["land_details"]).select { |r| r.is_a?(Hash) }
      row = rows.find { |r| r["village_id"].present? } || rows.first
      state_id = row&.dig("state_id").presence&.to_s
      places = AsaLocationNames.for_land_row(row)

      if state_id.blank? && places.blank?
        puts "  #{login.full_name} (##{login.id}): register has no land details, nothing to fill"
        next
      end

      login.update!(
        state_id: login.state_id.presence || state_id,
        village_name: login.village_name.presence || places[:village_name],
        block_name: login.block_name.presence || places[:block_name],
        district_name: login.district_name.presence || places[:district_name],
        state_name: login.state_name.presence || places[:state_name]
      )
      filled += 1
      puts "  #{login.full_name} (##{login.id}): state=#{login.reload.state_name.presence || state_id || '-'} " \
           "#{[places[:village_name], places[:district_name]].compact.join(', ')}"
    end

    puts "Filled #{filled} row(s)."
  end
end
