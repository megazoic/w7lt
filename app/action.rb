require_relative '../config/sequel'

module MemberTracker
  class Action < Sequel::Model
    #expect this table to hold mbr_edit, mbr_renew, login
    one_to_many :logs, :class=>"MemberTracker::Log", key: :action_id
  end
end
