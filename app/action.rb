require_relative '../config/sequel'

module MemberTracker
  class Action < Sequel::Model
    #expect this table to hold mbr_edit, mbr_renew, login, volunteer_hrs, auth_u, unit, donation, event
    one_to_many :logs, :class=>"MemberTracker::Log", key: :action_id
  end
end
