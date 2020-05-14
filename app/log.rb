require_relative '../config/sequel'
module MemberTracker
  class Log < Sequel::Model
    many_to_one :action, :class=>Action, key: :action_id
    many_to_one :auth_user, :class=>Auth_user, key: :a_user_id
    many_to_one :member, :class=>Member, key: :mbr_id
    many_to_one :unit, :class=>Unit, key: :unit_id
    many_to_one :event, :class=>"MemberTracker::Event", key: :event_id
    one_to_one :payment, :class=>"MemberTracker::Payment", key: :log_id
  end
end
#********************Log Notes*******************
#
# => use "Unit mbr association[(+/-)mbr_id:nn]" to record
# => changes of members in a unit
#
#*************************************************