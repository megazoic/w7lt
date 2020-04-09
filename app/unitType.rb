require_relative '../config/sequel'

module MemberTracker
  class UnitType < Sequel::Model
    one_to_many :units, :class=>"MemberTracker::Unit", key: :unit_type_id
  end
end