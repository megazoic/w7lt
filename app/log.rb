require_relative '../config/sequel'
module MemberTracker
  class Log < Sequel::Model
    many_to_one :action, :class=>Action, key: :action_id
    many_to_one :auth_user, :class=>Auth_user, key: :a_user_id
    many_to_one :member, :class=>Member, key: :mbr_id
    many_to_one :unit, :class=>Unit, key: :unit_id
    many_to_one :event, :class=>"MemberTracker::Event", key: :event_id
    one_to_one :payment, :class=>"MemberTracker::Payment", key: :log_id
    def Log.getActionID(name)
      #pick up the action id for the 'name' action
      lats = DB.from(:actions).select(:id, :name).all
      lat_id = ''
      lats.each do |l|
        if l[:name] == name
          lat_id = l[:id]
        end
      end
      lat_id
    end

  end
end
#********************Log Notes*******************
#
# => use "Unit mbr association[(+/-)mbr_id:nn]" to record
# => changes of members in a unit
#
#*************************************************
