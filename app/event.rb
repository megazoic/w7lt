require_relative '../config/sequel'

module MemberTracker
  class Event < Sequel::Model
    many_to_many :members, left_key: :event_id, right_key: :mbr_id, join_table: :members_events
    many_to_one :event_type
    many_to_one :auth_user, key: :a_user_id
    one_to_many :log, :class =>"MemberTracker::Log", key: :event_id

    Guest = Struct.new(:number, :attendees, :new_guests, :tmp_vitals, :msng_values, :duplicate)
    #Struct holds attendees (mbrs who are already in db), new_guests (those to be entered), vitals a temp hash
    #access number of members attending an event
    def member_count()
      #for now, will be returning the count of one event type Monthly Meetings
      #pull all events of the types associated with this group (monthly-inperson => 10,
      #monthly-on_zoom => 11 and monthly meeting OLD => 2) which coresponds to EventType::EVENT_TYPE_OPTIONS
      #want event, associated members count and time
      event_types = [10,11,2]
      #this array will hold hashes for each event by date with member counts for each event type
      all_event_details = []
      #fist, get dates for events of these types
      #loop through each event type
      event_types.each do |et|
        events = Event.where(event_type_id: et).order(:ts).all
        events.each do |e|
          event_details = {}
          event_details[:event_id] = e.id
          event_details[:event_type_id] = et
          event_details[:event_date] = e.ts.strftime("%Y-%m-%d")
          event_details[:member_count] = e.members.count
          #truncate event name and description to fit in display
          event_details[:event_name] = e.name.length > 30 ? e.name[0..29] : e.name
          event_details[:description] = e.descr.length > 50 ? e.descr[0..49] : e.descr
          all_event_details << event_details
        end
      end
      if all_event_details.empty?
        return nil
      else
        return all_event_details
      end
    end
  end
end
