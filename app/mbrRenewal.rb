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
      #from call to this method
      #mbrs2renw_mbrRnwl << {mr[:id] => {:fname => mr[:fname], :lname => mr[:lname],
      #:callsign => mr[:callsign], :email => mr[:email], :mbr_type => mr[:mbr_type]}}
      purged_hash = {}
      mbrs2rnw_hash.each do |mbr_id_k,v|
        #remove mbrs who do not have family mbr_type
        if Member[mbr_id_k].mbr_type != 'family'
          purged_hash << {mbr_id_k => v}
        else #need to find paying member of family unit and purge the others
          if Member[mbr_id_k].units.nil?
            return "error mbr #{mbr_id_k}, should have at least a family unit, no unit found"
          end
          #find members in this family unit, mbrs2purge is array of hashes with unit_id as key and value array of mbr_ids
          mbrs2purge = []
          Member[mbr_id_k].units.each do |u|
            #which one of these is the family unit?
            if u.unit_type_id == UnitType.getID("family")
              #collect ids from all family members of this unit
              #find which one made the most recent payment and check that was a dues payment for a family mbr type
              #finally, add that member to the purged_hash, throw error if don't have a result here
              #have we already discovered this family Unit?
              if mbrs2purge.include?(u.id)
                #will want to skip this mbr_id if it is already in the hash for this unit (which it should be!)
                if !mbrs2purge[u].include?(mbr_id_k)
                  #there is something wrong here this mbr_id should already be in the array of members of this unit
                  return "error mbr #{mbr_id_k} missing from existing family unit #{u.id}"
                end
              else #we haven't encountered this family unit, let's get it's members
                fam_mbr_array = []
                u.members.each do |m|
                  fam_mbr_array << m.id
                end
                mbrs2purge[u.id] = fam_mbr_array
              end
            end
            if mbrs2purge.empty?
              return "error mbr #{mbr_id_k} should have family unit, no family unit found"
            end
          end #now have array with hashes (key is unit_id) holding all members of a family unit, find paying member
          mbrs2purge.each do |u_id,v|
            mbr_with_latest_dues = nil
            latest_dues_pmt_for_fam_unit = nil
            v.each do |mbr_id|
              dues_pmt_for_fam_unit = Payment.findLatestDues(mbr_id, "dues")
              #did we find a dues payment?
              if !dues_pmt_for_fam_unit.nil?
                if latest_dues_pmt_for_fam_unit < dues_pmt_for_fam_unit
                  latest_dues_pmt_for_fam_unit = dues_pmt_for_fam_unit
                  mbr_with_latest_dues = mbr_id
                end
              end
            end
            #should have the mbr_id of the latest dues paying family mbr need to add that to purged_hash
            if mbr_with_latest_dues.nil?
              return "error could not find any dues payments for unit #{u_id}"
            else
              purged_hash << mbr_with_latest_dues
            end
          end
        end
      end
    end
  end
end
