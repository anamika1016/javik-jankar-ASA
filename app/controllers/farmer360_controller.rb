# Farmer 360: look a farmer up in the ASA register by mobile or Aadhaar and show
# whatever that record holds. Read-only -- nothing here writes to our database.
class Farmer360Controller < ApplicationController
  def index
    @mobile_no = params[:mobile_no].to_s.strip
    @aadhaar_no = params[:aadhaar_no].to_s.strip
    return if @mobile_no.blank? && @aadhaar_no.blank?

    lookup = if @mobile_no.present?
      FarmerRegisterLookup.by_mobile(@mobile_no)
    else
      FarmerRegisterLookup.by_aadhaar(@aadhaar_no)
    end

    @result = lookup.farmer
    @error = lookup.error
  end
end
