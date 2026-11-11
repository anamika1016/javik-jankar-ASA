# A news post shown in the Android farmer app.
class FarmerNewsItem < ApplicationRecord
  self.table_name = "farmer_news"

  include FarmerBroadcast
end
