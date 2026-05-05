require_relative '../config/sequel'

module MemberTracker
  class MbrRenewal < Sequel::Model
    one_to_many :log, :class =>"MemberTracker::Log", key: :mbr_renewal_id
    many_to_one :auth_user, :class=>AuthUser, key: :a_user_id
    many_to_one :member, :class=>Member, key: :mbr_id
    many_to_one :renewalEventType
    RENEWAL_WINDOW = 14 #14 days = 2 weeks
    RENEW_TOO_EARLY = 334 #31 days, compare today's date with (mbrship_renewal_date + RENEW_TOO_EARLY)
    class << self
      attr_reader :mbr_types, :modes
    end
    def MbrRenewal.get2ndNotice
      #looking for mbrs with active renewals who have had a first reminder sent (but no second reminder) > 1 week ago
      mbrs_to_send_2nd_notice = []
      r_sent_ret_id = RenewalEventType.getID("1st reminder sent")
      r_2nd_notice_ret_id = RenewalEventType.getID("2nd reminder sent")
      mbrs_active_renewal = DB[:members].select(:id, :fname, :lname, :callsign, :email).where(mbrship_renewal_active: true)
      m_rmdr1_snt = DB[:mbr_renewals].select(:mbr_id).where(renewal_event_type_id: r_sent_ret_id).where(ts: (Date.today - 28)...( Date.today -7)).all.map{|n| n[:mbr_id]}
      m_rmdr2_snt = DB[:mbr_renewals].select(:mbr_id).where(renewal_event_type_id: r_2nd_notice_ret_id).all.map{|n| n[:mbr_id]}
      mbrs_w_only_1rnwl = []
      #test for empty set, then remove those who already have a second renewal
      if m_rmdr1_snt.empty?
        mbrs_to_send_2nd_notice = ["empty"]
      else
        mbrs_w_only_1rnwl = m_rmdr1_snt.delete_if {|entry| m_rmdr2_snt.include?(entry)}
        mbrs_active_renewal.each do |mar|
          if mbrs_w_only_1rnwl.include?(mar[:id])
            mbrs_to_send_2nd_notice << mar
          end
        end
        if mbrs_to_send_2nd_notice.empty?
          mbrs_to_send_2nd_notice = ["empty"]
        end
      end
      mbrs_to_send_2nd_notice
    end
    def MbrRenewal.getRenewRangeStart(auth_user_id)
      #return the date of latest entry that corresponds to latest log with action id = 'mbr_renew_check'
      #OLD-->either a reminder was sent or a missing email discovered * RENEWAL_WINDOW (weeks)<--OLD
      #look up last mbr_renew_check in log
      latest_renew_check = DB.from(:logs).where(action_id: Action.get_action_id("mbr_renew_check")).reverse_order(:ts).first
      date = Date.parse(latest_renew_check[:ts].to_s)
      #rs_id = RenewalEventType.getID("1st reminder sent")
      #no_eml = RenewalEventType.getID("missing email")
      #latest_hash = DB.from(:mbr_renewals).where(renewal_event_type_id: [rs_id, no_eml]).reverse_order(:ts).first
      #date = Date.parse(latest_hash[:ts].to_s)
      #catch entry that is same as today (i.e. already checked today)
      if date > Date.today
        return "error"
      elsif date == Date.today
        return "wait"
      end

      date - (365 - RENEWAL_WINDOW)
    end
    def MbrRenewal.getNewMbrshipRenewalDate(mbr_id, mbr_type)
      renewal_date = nil
      if ['lifetime', 'honorary'].include?(mbr_type)
        return DateTime.new(2100,01,01)
      end
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
          renewal_date = DateTime.now
        end
      else #no prior renewal date
        renewal_date = DateTime.now
      end
      renewal_date
    end
    def MbrRenewal.findAndPurgeFamily(mbrs2rnw_hash)
      purged_hash = {}
      mbrs2rnw_hash.each do |mbr_id_k, mbr_data|
        if Member[mbr_id_k].mbr_type != 'family'
          purged_hash[mbr_id_k] = mbr_data
        else
          if Member[mbr_id_k].units.empty?
            return "error mbr #{mbr_id_k}, should have at least a family unit, no unit found"
          end
          # Map of unit_id => [mbr_id, ...] for each family unit this member belongs to
          mbrs2purge = {}
          Member[mbr_id_k].units.each do |u|
            next unless u.unit_type_id == UnitType.getID("family")
            if mbrs2purge.key?(u.id)
              unless mbrs2purge[u.id].include?(mbr_id_k)
                return "error mbr #{mbr_id_k} missing from existing family unit #{u.id}"
              end
            else
              mbrs2purge[u.id] = u.members.map(&:id)
            end
          end
          if mbrs2purge.empty?
            return "error mbr #{mbr_id_k} should have family unit, no family unit found"
          end
          mbrs2purge.each do |u_id, mbr_ids|
            mbr_with_latest_dues = nil
            latest_dues_ts = nil
            mbr_ids.each do |mbr_id|
              ts = Payment.findLatestDues(mbr_id, "Dues")
              next if ts.nil?
              if latest_dues_ts.nil? || ts > latest_dues_ts
                latest_dues_ts = ts
                mbr_with_latest_dues = mbr_id
              end
            end
            if mbr_with_latest_dues.nil?
              return "error could not find any dues payments for unit #{u_id}"
            end
            purged_hash[mbr_with_latest_dues] = mbrs2rnw_hash.fetch(mbr_with_latest_dues) do
              m = Member[mbr_with_latest_dues]
              { fname: m.fname, lname: m.lname, callsign: m.callsign,
                email: m.email, mbr_type: m.mbr_type }
            end
          end
        end
      end
      purged_hash
    end
  end
end
