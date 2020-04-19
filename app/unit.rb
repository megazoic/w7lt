require_relative '../config/sequel'

module MemberTracker
  class Unit < Sequel::Model
    many_to_many :members, left_key: :unit_id, right_key: :mbr_id, join_table: :members_units
    many_to_one :unit_type
    many_to_one :auth_user, key: :a_user_id
    one_to_many :log, :class =>"MemberTracker::Log", key: :unit_id
  end
end