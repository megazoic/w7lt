require_relative '../config/sequel'

module MemberTracker
  class Event < Sequel::Model
    many_to_many :members, left_key: :event_id, right_key: :mbr_id, join_table: :members_events
    many_to_one :event_type
    many_to_one :auth_user, key: :a_user_id
    one_to_many :log, :class =>"MemberTracker::Log", key: :event_id
    
    Guest = Struct.new(:number, :attendees, :new_guests, :tmp_vitals, :msng_values, :duplicate)
    #Struct holds attendees (mbrs who are already in db), new_guests (those to be entered), vitals a temp hash
  end
end