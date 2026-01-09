require_relative '../config/sequel'

module MemberTracker
  class EventType < Sequel::Model
    one_to_many :events, :class=>"MemberTracker::Event", key: :event_type_id
    many_to_one :auth_users, :class=> "MemberTracker::Auth_user", key: :a_user_id
    # Make a hash of event types for use in select options
    EVENT_TYPE_OPTIONS =  {"1"=>"General Meeting", "2"=>"POTA", "3"=>"Field Day", "4"=>"Holiday & BBQ", "5"=> "Board Meeting"}
  end
end
