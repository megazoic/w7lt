require_relative '../config/sequel'
# member actions are things we need to track that require an action by a different member
# eg follow up phone call
module MemberTracker
  class MemberAction < Sequel::Model
    many_to_one :auth_user
    many_to_one :member_action_type
    many_to_one :member
    #add method to get member actions
    def self.get_member_actions(action_type_id)
      #action_type_id is an int from the member_action_types table
      #returns an array of hashes with the member actions and notification if log notes exist for a given type
      actions = []
      member_actions = MemberAction.where(member_action_type_id: action_type_id, completed: false).select(:id, :member_target, :tasked_to_mbr_id,
        :a_user_id, :notes, :ts).reverse_order(:ts).all
      member_actions.each do |ma|
        #get the member name from the member table
        mbr = Member.where(id: ma.member_target).select(:fname, :lname, :callsign).first
        if mbr
          #build auth user name
          a_user_name = "#{Auth_user.where(id: ma.a_user_id).first.member.fname} #{Auth_user.where(id: ma.a_user_id).first.member.lname}"
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
          actions << ma_hash
        else
          puts "MemberAction.get_member_actions: no member found for id #{ma.member_target}"
        end
      end
      return actions
    end
  end
end
