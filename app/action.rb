require_relative '../config/sequel'

module MemberTracker
  class Action < Sequel::Model
    #expect this table to hold mbr_edit, mbr_renew, login, volunteer_hrs, auth_u, unit, donation, event, general_log
    one_to_many :logs, :class=>"MemberTracker::Log", key: :action_id
    def get_action_id(a_type)
      action_array = Action.select(:id, :type).all
      action_hash = {}
      action_array.map(){|x| action_hash[x[:type]] = x[:id]}
      action_hash[a_type]
    end
  end
end
