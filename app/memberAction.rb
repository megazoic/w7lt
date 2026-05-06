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
      member_actions = MemberAction
        .where(member_action_type_id: action_type_id, completed: false)
        .select(:id, :member_target, :tasked_to_mbr_id, :a_user_id, :notes, :ts)
        .reverse_order(:ts).all
      return [] if member_actions.empty?

      target_ids  = member_actions.map(&:member_target).uniq
      a_user_ids  = member_actions.map(&:a_user_id).uniq
      tasked_ids  = member_actions.map(&:tasked_to_mbr_id).compact.uniq
      action_ids  = member_actions.map(&:id)

      members_by_id  = Member.where(id: (target_ids + tasked_ids).uniq).all
                             .each_with_object({}) { |m, h| h[m.id] = m }
      auth_users_by_id = AuthUser.where(id: a_user_ids).all
                                 .each_with_object({}) { |au, h| h[au.id] = au }
      au_mbr_ids = auth_users_by_id.values.map(&:mbr_id).uniq
      au_members_by_id = Member.where(id: au_mbr_ids).all
                               .each_with_object({}) { |m, h| h[m.id] = m }

      has_log_ids = DB[:logs].where(mbr_action_id: action_ids)
                             .distinct.select_map(:mbr_action_id).to_set

      attended_ids = DB[:members_events]
        .join(:events, id: :event_id)
        .where(Sequel[:members_events][:member_id] => target_ids)
        .where(Sequel[:events][:ts] > (Date.today - 90).to_time)
        .distinct
        .select_map(Sequel[:members_events][:member_id])
        .to_set

      member_actions.each_with_object([]) do |ma, actions|
        mbr = members_by_id[ma.member_target]
        next unless mbr

        au     = auth_users_by_id[ma.a_user_id]
        au_mbr = au ? au_members_by_id[au.mbr_id] : nil
        tasked = members_by_id[ma.tasked_to_mbr_id]

        actions << {
          id:                 ma.id,
          target_member_id:   ma.member_target,
          target_member_name: "#{mbr.fname} #{mbr.lname}",
          tasked_to_mbr_id:   ma.tasked_to_mbr_id,
          tasked_to:          tasked ? "#{tasked.fname} #{tasked.lname}" : "Unassigned",
          a_user_name:        au_mbr ? "#{au_mbr.fname} #{au_mbr.lname}" : "Unknown",
          notes:              ma.notes,
          ts:                 ma.ts.strftime("%m-%d-%Y"),
          has_logs:           has_log_ids.include?(ma.id),
          attended_meeting:   attended_ids.include?(ma.member_target)
        }
      end
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
