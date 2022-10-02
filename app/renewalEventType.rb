require_relative '../config/sequel'

module MemberTracker
  class RenewalEventType < Sequel::Model
    one_to_many :mbr_renewals, :class=>"MemberTracker::MbrRenewal", key: :renewal_event_type_id
    many_to_one :auth_users, :class=> "MemberTracker::Auth_user", key: :a_user_id
  end
  def RenewalEventType.getID(name)
    rets = DB.from(:renewal_event_types).select(:id, :name).all
    ret_id = ''
    rets.each do |r|
      if r[:name] == name
        ret_id = r[:id]
      end
    end
    ret_id
  end
end