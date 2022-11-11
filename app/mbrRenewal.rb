require_relative '../config/sequel'

module MemberTracker
  class MbrRenewal < Sequel::Model
    one_to_many :log, :class =>"MemberTracker::Log", key: :mbr_renewal_id
    many_to_one :auth_user, :class=>Auth_user, key: :a_user_id
    many_to_one :member, :class=>Member, key: :mbr_id
    many_to_one :renewalEventType
    RENEWAL_WINDOW = 14 #14 days = 2 weeks
    RENEW_TOO_EARLY = 334 #31 days, compare today's date with (mbrship_renewal_date + RENEW_TOO_EARLY)
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
      if date > Date.today 
        return "error"
      elsif date == Date.today
        return "wait"
      end
      date - (365 - RENEWAL_WINDOW)
    end
    def MbrRenewal.getNewMbrshipRenewalDate(mbr_id)
      renewal_date = nil
      #calculate the new date based on renewal event today
      if !Member[mbr_id].mbrship_renewal_date.nil?
        begin_date_window = Date.parse(Member[mbr_id].mbrship_renewal_date.to_s) + 334
        end_date_window = Date.parse(Member[mbr_id].mbrship_renewal_date.to_s) + 379
        today = Date.parse(Time.now.to_s)
        if (begin_date_window...end_date_window).include?(today)
          #within window, just update the existing Time
          new_mrd = Date.parse(Member[mbr_id].mbrship_renewal_date.to_s)+365
          renewal_date = DateTime.parse(new_mrd.to_s)
        else
          #changing mbrship_renewal_date since either too early or too late
          renewal_date = Time.now
        end
      else #no prior renewal date
        renewal_date = Time.now
      end
      renewal_date
    end
    def MbrRenewal.findAndPurgeFamily(mbrs2rnw_hash)
      purged_hash = {}
      mbrs2rnw_hash.each do |k,v|
        #remove mbrs who do not have family mbr_type
        if Member[k].mbr_type != 'family'
          purged_hash << {k => v}
        else
          #find members in this unit
          mbrs2purge = []
          Member[k].units.each do |u|
            if UnitType.getID("family") == u.unit_type_id
              #check that they all have the same mbrship_renewal_date first
              #then find which one made the most recent payment and check that was a dues payment for a family mbr type
              #finally, add that member to the purged_hash, throw error if don't have a result here
              u.members.each do |m|
              end
            end
          end
        end
      end
    end
  end
end
