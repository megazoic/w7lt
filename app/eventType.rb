require_relative '../config/sequel'

module MemberTracker
  class EventType < Sequel::Model
    one_to_many :events, :class=>"MemberTracker::Event", key: :event_type_id
    many_to_one :auth_users, :class=> "MemberTracker::Auth_user", key: :a_user_id
  end
end