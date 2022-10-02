require_relative '../config/sequel'

module MemberTracker
  class MbrRenewal < Sequel::Model
    one_to_many :log, :class =>"MemberTracker::Log", key: :mbr_renewal_id
    many_to_one :auth_user, :class=>Auth_user, key: :a_user_id
    many_to_one :member, :class=>Member, key: :mbr_id
    many_to_one :renewalEventType
    RENEWAL_WINDOW = 14 #14 days = 2 weeks
    class << self
      attr_reader :mbr_types, :modes
    end
    
    def MbrRenewal.getRenewRangeStart
      #return the date of latest entry that corresponds to either a reminder was sent or
      #a missing email discovered * RENEWAL_WINDOW (weeks)
      rs_id = RenewalEventType.getID("reminder sent")
      no_eml = RenewalEventType.getID("missing email")
      latest_hash = DB.from(:mbr_renewals).where(renewal_event_type_id: [rs_id, no_eml]).reverse_order(:ts).first
      date = Date.parse(latest_hash[:ts].to_s)
      #catch entry that is same as today (i.e. already checked today)
      if date >= Date.today 
        return "error"
      end
      date - (365 - RENEWAL_WINDOW)
=begin
      renwl_recs = DB.from(:mbr_renewals).select(:renewal_event_type_id, :ts).all
      d = Date.today
      date = Date.civil(d.year-1, d.month, d.day)
      date = Time.parse(date.to_s)
      renwl_recs.each do |rr|
        if (rr[:renewal_event_type_id] == (rs_id | no_eml))
          puts "in renwl_rec condition met and date: #{date}"
          date = rr[:ts] if (rr[:ts] > date)
        end
      end
      #need date format
      date = Date.parse(date.to_s)
      #find date that is year earlier + 2 weeks
      date - (365 - RENEWAL_WINDOW)
=end
    end
    def MbrRenewal.cmparePmtWithMbr(mbr, pmt)
      #need to parse out these two arrays and obtain 5 separate collections
    end
  end
end
