require_relative '../config/sequel'
# member actions are things we need to track that require an action by a different member
# eg follow up phone call
module MemberTracker
  class MemberAction < Sequel::Model
    many_to_one :auth_user
    many_to_one :member_action_type
    many_to_one :member

    STALE_AFTER_MONTHS = 4
    #add method to get member actions
    def self.get_member_actions(action_type_id)
      #action_type_id is an int from the member_action_types table
      #returns an array of hashes with the member actions and notification if log notes exist for a given type
      actions = []
      member_actions = MemberAction.where(member_action_type_id: action_type_id, completed: false).select(:id, :member_target, :tasked_to_mbr_id,
        :a_user_id, :notes, :ts).reverse_order(:ts).all
      member_actions.each do |ma|
        #get the member name from the member table
        mbr = Member.where(id: ma.member_target).first
        if mbr
          #build auth user name
          a_user_name = "#{AuthUser.where(id: ma.a_user_id).first.member.fname} #{AuthUser.where(id: ma.a_user_id).first.member.lname}"
          #build the tasked to member name
          tasked_to_mbr = Member.where(id: ma.tasked_to_mbr_id).select(:fname, :lname, :callsign).first
          if tasked_to_mbr
            ma_tasked_to_name = "#{tasked_to_mbr.fname} #{tasked_to_mbr.lname}"
          else
            ma_tasked_to_name = "Unassigned"
          end
          ma_hash = {
            id: ma.id,
            target_member_id: ma.member_target,
            target_member_name: "#{mbr.fname} #{mbr.lname}",
            tasked_to_mbr_id: ma.tasked_to_mbr_id,
            tasked_to: ma_tasked_to_name,
            a_user_name: a_user_name,
            notes: ma.notes,
            ts: ma.ts.strftime("%m-%d-%Y")
          }
          #check if there are any logs for this member action
          ma_hash[:has_logs] = false
          logs = DB[:logs].where(mbr_action_id: ma.id, mbr_id: ma.member_target).all
          if logs && logs.length > 0
            ma_hash[:has_logs] = true
          end
          #check if this member attended a meeting within the last 90 days
          ma_hash[:attended_meeting] = false
          mbr.events.each do |event|
            if event[:ts].to_date > (Date.today - 90)
              ma_hash[:attended_meeting] = true
              break
            end
          end
          actions << ma_hash
        end
      end
      return actions
    end
    # Returns completed call_member actions ordered most-recent first.
    def self.get_completed_call_actions
      call_type_id = MemberActionType[name: 'call_member'].id
      actions = []
      MemberAction.where(member_action_type_id: call_type_id, completed: true)
                  .reverse_order(:ts).each do |ma|
        mbr = Member.where(id: ma.member_target).first
        next unless mbr
        au = AuthUser.where(id: ma.a_user_id).first
        a_user_name = au ? "#{au.member.fname} #{au.member.lname}" : "Unknown"
        tasked_to_mbr = Member.where(id: ma.tasked_to_mbr_id).select(:fname, :lname).first
        actions << {
          id:                 ma.id,
          target_member_id:   ma.member_target,
          target_member_name: "#{mbr.fname} #{mbr.lname}",
          a_user_name:        a_user_name,
          tasked_to:          tasked_to_mbr ? "#{tasked_to_mbr.fname} #{tasked_to_mbr.lname}" : "Unassigned",
          notes:              ma.notes,
          ts:                 ma.ts.strftime("%m-%d-%Y"),
          has_logs:           DB[:logs].where(mbr_action_id: ma.id, mbr_id: ma.member_target).count > 0
        }
      end
      actions
    end

    # Marks call_member actions older than STALE_AFTER_MONTHS as completed and
    # writes a log entry for each, linked via mbr_action_id.
    # Returns the count of actions expired.
    def self.expire_stale_call_actions(auth_user_id)
      call_type_id = MemberActionType[name: 'call_member'].id
      cutoff       = DateTime.now << STALE_AFTER_MONTHS
      stale = MemberAction.where(member_action_type_id: call_type_id, completed: false)
                          .where(Sequel[:ts] < cutoff).all
      return 0 if stale.empty?

      log_action_id = Action.get_action_id('mbr_call_me')
      stale.each do |ma|
        DB.transaction do
          DB[:member_actions].where(id: ma.id).update(completed: true)
          Log.new(
            mbr_id:        ma.member_target,
            a_user_id:     auth_user_id,
            ts:            Time.now,
            action_id:     log_action_id,
            mbr_action_id: ma.id,
            notes:         "Call-member action auto-completed: no resolution recorded after #{STALE_AFTER_MONTHS} months"
          ).save
        end
      end
      stale.size
    end

    def self.build_log_notes(mbr_action, params)
      #build log notes for the member action
      log_notes = "making changes to mbr_action record id: #{mbr_action[:id]}\n"
      mbr_action.each do |k,v|
        if (k == :tasked_to_mbr_id && v != params[:tasked_to_mbr_id])
          log_notes << "tasked_to_mbr_id: old record: #{v}, new record: #{params[:tasked_to_mbr_id]}\n"
        else
          #check if the value in params is different from the value in mbr_action
          next if params[k].nil? || params[k] == v
          #if it is different then add to log notes
          log_notes << "#{k}: old record: #{v}, new record: #{params[k]}\n"
        end
      end
      return log_notes
    end
  end
end
