require_relative '../config/sequel'

module MemberTracker
  class ReferType < Sequel::Model
    one_to_many :members, :class=>"MemberTracker::Member", key: :refer_type_id
  end
end