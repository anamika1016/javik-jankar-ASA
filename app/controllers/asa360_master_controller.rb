class Asa360MasterController < ApplicationController
  def index
    @records = Asa360Master.order(:o_type, :o_name)
  end
end
