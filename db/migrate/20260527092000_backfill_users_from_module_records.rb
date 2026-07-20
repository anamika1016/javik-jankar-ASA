class BackfillUsersFromModuleRecords < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:module_records) && table_exists?(:users)

    select_all("SELECT data, created_at, updated_at FROM module_records WHERE module_slug = 'new-user'").each do |row|
      data = JSON.parse(row["data"]) rescue {}
      next if data["user_name"].blank?
      next if user_exists?(data["user_name"])

      execute <<~SQL.squish
        INSERT INTO users (
          stakeholder, role, state, district, block, gram_panchayat, village,
          parent_office, office, full_address, pincode, first_name, last_name,
          gender, age, email, password, user_name, mobile_no, emergency_no,
          user_type, status, created_at, updated_at
        ) VALUES (
          #{quote(data["stakeholder"])}, #{quote(data["role"])}, #{quote(data["state"])},
          #{quote(data["district"])}, #{quote(data["block"])}, #{quote(data["gram_panchayat"])},
          #{quote(data["village"])}, #{quote(data["parent_office"])}, #{quote(data["office"])},
          #{quote(data["full_address"])}, #{quote(data["pincode"])}, #{quote(data["first_name"])},
          #{quote(data["last_name"])}, #{quote(data["gender"])}, #{quote(data["age"].presence&.to_i)},
          #{quote(data["email"])}, #{quote(data["password"])}, #{quote(data["user_name"])},
          #{quote(data["mobile_no"])}, #{quote(data["emergency_no"])}, #{quote(data["user_type"])},
          #{quote(data["status"].presence || "Active")}, #{quote(row["created_at"])}, #{quote(row["updated_at"])}
        )
      SQL
    end
  end

  def down
  end

  private

  def user_exists?(user_name)
    select_value("SELECT 1 FROM users WHERE user_name = #{quote(user_name)} LIMIT 1").present?
  end
end
